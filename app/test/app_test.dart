import 'dart:convert';

import 'package:diarias/api/api_client.dart';
import 'package:diarias/main.dart';
import 'package:diarias/screens/home_screen.dart';
import 'package:diarias/state/app_state.dart';
import 'package:diarias/theme/app_theme.dart';
import 'package:diarias/widgets/ds_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// August 2026, matching the design prototype's seeded month.
final _today = DateTime(2026, 8, 12);

Map<String, dynamic> _provider(String id, String name, int colorIndex) => {
  'id': id,
  'name': name,
  'default_rate_cents': 18000,
  'color_index': colorIndex,
  'position': colorIndex,
};

/// Serves the canned month used by every test below: Marina paid R$ 180,00 on
/// the 3rd, Cleide still owed R$ 150,00 for the 5th.
http.Client _fakeApi({
  List<String>? recordedPaths,
  int outstandingCents = 15000,
}) {
  return MockClient((request) async {
    recordedPaths?.add('${request.method} ${request.url.path}');
    final path = request.url.path;

    // Unmarking a day returns no content, like the real API.
    if (path == '/api/v1/entries' && request.method == 'DELETE') {
      return http.Response('', 204);
    }
    // Marking a day returns the single upserted entry, not the month's list.
    if (path == '/api/v1/entries' && request.method == 'PUT') {
      return http.Response(
        jsonEncode({
          'id': 'new',
          'provider_id': 'p1',
          'date': '2026-08-05',
          'value_cents': 18000,
        }),
        200,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );
    }

    final body = switch (path) {
      '/api/v1/providers' => [
        _provider('p1', 'Marina Souza', 0),
        _provider('p2', 'Cleide Ramos', 1),
      ],
      '/api/v1/entries' => [
        {
          'id': 'e1',
          'provider_id': 'p1',
          'date': '2026-08-03',
          'value_cents': 18000,
        },
        {
          'id': 'e2',
          'provider_id': 'p2',
          'date': '2026-08-05',
          'value_cents': 15000,
        },
      ],
      _ when path.startsWith('/api/v1/months/') => {
        'year': 2026,
        'month': 8,
        'total_cents': 33000,
        'outstanding_cents': outstandingCents,
        'worked_days': 2,
        'providers': [
          {
            'provider': _provider('p1', 'Marina Souza', 0),
            'entry_count': 1,
            'total_cents': 18000,
            'paid': true,
            'days': [
              {'date': '2026-08-03', 'value_cents': 18000},
            ],
          },
          {
            'provider': _provider('p2', 'Cleide Ramos', 1),
            'entry_count': 1,
            'total_cents': 15000,
            'paid': false,
            'days': [
              {'date': '2026-08-05', 'value_cents': 15000},
            ],
          },
        ],
      },
      _ => <String, dynamic>{},
    };

    return http.Response(
      jsonEncode(body),
      200,
      headers: {'content-type': 'application/json; charset=utf-8'},
    );
  });
}

/// Pumps the real app shell against [client], with the state already loaded.
///
/// The surface is set to the design's iPhone frame (402x874) rather than the
/// test default, so what is above and below the fold matches the real app —
/// tests scroll to reach lower content instead of pretending it all fits.
Future<AppState> pumpApp(WidgetTester tester, http.Client client) async {
  tester.view.physicalSize = const Size(402, 874);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);

  final state = AppState(
    api: ApiClient(
      baseUrl: Uri.parse('http://test.local'),
      httpClient: client,
    ),
    today: _today,
  );
  addTearDown(state.dispose);

  await tester.pumpWidget(
    MaterialApp(
      theme: AppTheme.build(),
      home: AppScope(notifier: state, child: const HomeScreen()),
    ),
  );
  await state.load();
  await tester.pumpAndSettle();
  return state;
}

/// Scrolls the active tab's list until [finder] is on screen.
Future<void> scrollTo(WidgetTester tester, Finder finder) async {
  await tester.dragUntilVisible(
    finder,
    find.byType(ListView),
    const Offset(0, -120),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('calendar tab shows the month and the outstanding total', (
    tester,
  ) async {
    await pumpApp(tester, _fakeApi());

    // The header's "A pagar" is the outstanding amount, not the month total.
    expect(find.text(r'R$ 150,00'), findsWidgets);
    expect(find.text(r'R$ 33.000,00'), findsNothing);

    // Header title and the month card's navigation label.
    expect(find.text('Agosto de 2026'), findsNWidgets(2));
    expect(find.text('MARCAR DIAS'), findsOneWidget);

    // 31 day cells for August.
    expect(find.text('31'), findsOneWidget);

    // Legend chips use first names and a day count.
    expect(find.text('Marina'), findsOneWidget);
    expect(find.text('Cleide'), findsOneWidget);

    // "Últimos lançamentos" sits below the fold on a real phone.
    await scrollTo(tester, find.text('Marina Souza'));
    expect(find.text('Marina Souza'), findsOneWidget);
    expect(find.text('segunda, 3 de agosto'), findsOneWidget);
  });

  testWidgets('switching to Fechamento shows totals and payment status', (
    tester,
  ) async {
    await pumpApp(tester, _fakeApi());

    await tester.tap(find.text('Fechamento'));
    await tester.pumpAndSettle();

    // Marina's card is first and already paid.
    expect(find.text('Marina Souza'), findsOneWidget);
    expect(find.text('Total do mês'), findsWidgets);
    expect(find.text(r'R$ 180,00'), findsWidgets);
    expect(find.text('Pago'), findsOneWidget);
    expect(find.text('Desfazer pagamento'), findsOneWidget);

    // Cleide's card and the summary block are further down.
    await scrollTo(tester, find.text('Marcar como pago'));
    expect(find.text('Em aberto'), findsOneWidget);
    expect(find.text('Marcar como pago'), findsOneWidget);

    await scrollTo(
      tester,
      find.textContaining('1 prestadora ainda com valor em aberto'),
    );
    expect(
      find.textContaining('1 prestadora ainda com valor em aberto'),
      findsOneWidget,
    );
    expect(find.text('Fechamento de Agosto de 2026'), findsOneWidget);
  });

  testWidgets('Prestadoras tab lists names and default rates', (tester) async {
    await pumpApp(tester, _fakeApi());

    await tester.tap(find.text('Prestadoras'));
    await tester.pumpAndSettle();

    expect(find.text('Valor padrão da diária'), findsNWidgets(2));
    expect(find.text('+ Nova prestadora'), findsOneWidget);
    // Rates render inside the money field, without the R$ prefix.
    expect(find.text('180,00'), findsNWidgets(2));
  });

  testWidgets('tapping a day opens the "Quem trabalhou?" sheet', (
    tester,
  ) async {
    await pumpApp(tester, _fakeApi());

    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    expect(find.text('Quem trabalhou?'), findsOneWidget);
    expect(find.text('Quarta, 5 de agosto'), findsOneWidget);
    // Cleide worked that day; Marina did not, so she shows her default rate.
    expect(find.text('Trabalhou neste dia'), findsOneWidget);
    expect(find.text(r'Valor padrão R$ 180,00'), findsOneWidget);
    expect(find.text('Salvar dia'), findsOneWidget);
  });

  testWidgets('changing month refetches that month', (tester) async {
    final paths = <String>[];
    final state = await pumpApp(tester, _fakeApi(recordedPaths: paths));

    paths.clear();
    await tester.tap(find.bySemanticsLabel('Próximo mês'));
    await tester.pumpAndSettle();

    expect(state.month, 9);
    expect(paths, contains('GET /api/v1/months/2026/9'));
  });

  testWidgets('toggling a prestadora in the day sheet persists the day', (
    tester,
  ) async {
    final requests = <String>[];
    await pumpApp(tester, _fakeApi(recordedPaths: requests));

    // The 5th: Cleide worked, Marina did not.
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    requests.clear();
    // Marina's row is the unchecked one showing her default rate.
    await tester.tap(find.text(r'Valor padrão R$ 180,00'));
    await tester.pumpAndSettle();

    // Marking a day is an upsert; unmarking would be a DELETE.
    expect(requests, contains('PUT /api/v1/entries'));
    expect(
      requests.where((r) => r.startsWith('DELETE /api/v1/entries')),
      isEmpty,
    );

    // Cleide already worked, so tapping her row removes the day.
    requests.clear();
    await tester.tap(find.text('Trabalhou neste dia'));
    await tester.pumpAndSettle();
    expect(requests, contains('DELETE /api/v1/entries'));
  });

  testWidgets('marking a month paid calls the payment endpoint', (
    tester,
  ) async {
    final requests = <String>[];
    await pumpApp(tester, _fakeApi(recordedPaths: requests));

    await tester.tap(find.text('Fechamento'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Marcar como pago'));

    requests.clear();
    await tester.tap(find.text('Marcar como pago'));
    await tester.pumpAndSettle();

    // Cleide is the unpaid one, so it is her month that gets marked.
    expect(
      requests,
      contains('PUT /api/v1/months/2026/8/providers/p2/payment'),
    );
  });

  testWidgets('the share dialog previews the WhatsApp message', (tester) async {
    await pumpApp(tester, _fakeApi());

    await tester.tap(find.text('Fechamento'));
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text('Marcar como pago'));

    // "Enviar" on Cleide's card — the second one on screen.
    await tester.tap(find.text('Enviar').last);
    await tester.pumpAndSettle();

    expect(find.text('Enviar fechamento'), findsOneWidget);
    expect(find.text('Para Cleide Ramos, por WhatsApp'), findsOneWidget);
    expect(
      find.textContaining('Oi, Cleide! Fechamento de agosto:'),
      findsOneWidget,
    );
    expect(find.textContaining(r'1 diária · total R$ 150,00.'), findsOneWidget);
  });

  testWidgets('a large total does not push the header onto a second line', (
    tester,
  ) async {
    // Regression: on a 411dp phone, "R$ 1.720,00" left the title so little room
    // that "Agosto de 2026" wrapped and the whole header grew taller. The
    // header must stay a fixed height regardless of the amount, so the body
    // below it does not shift.
    await pumpApp(tester, _fakeApi(outstandingCents: 15000));
    final smallTotalBodyTop = tester
        .getTopLeft(find.byType(DsCard).first)
        .dy;

    await pumpApp(tester, _fakeApi(outstandingCents: 172000000));
    final largeTotalBodyTop = tester
        .getTopLeft(find.byType(DsCard).first)
        .dy;

    expect(find.text(r'R$ 1.720.000,00'), findsOneWidget);
    expect(largeTotalBodyTop, smallTotalBodyTop);
  });

  testWidgets('legend and status pills hug their content', (tester) async {
    await pumpApp(tester, _fakeApi());

    // The design's chips are inline-flex: a pill must not stretch to the full
    // row width.
    final chip = tester.getSize(
      find.ancestor(
        of: find.text('Marina'),
        matching: find.byType(DsPill),
      ),
    );
    expect(chip.width, lessThan(200));
    expect(chip.height, 30);
  });

  testWidgets('shows a retry affordance when the API is unreachable', (
    tester,
  ) async {
    final failing = MockClient(
      (_) async => throw http.ClientException('connection refused'),
    );
    await pumpApp(tester, failing);

    expect(find.text('Sem conexão com o servidor'), findsOneWidget);
    expect(find.text('Tentar de novo'), findsOneWidget);
  });
}
