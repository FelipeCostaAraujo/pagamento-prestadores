import 'dart:async';
import 'dart:convert';

import 'package:diarias/api/api_client.dart';
import 'package:diarias/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> _provider(String id, String name) => {
  'id': id,
  'name': name,
  'default_rate_cents': 17000,
  'color_index': 0,
  'position': 0,
};

Map<String, dynamic> get _emptyMonth => {
  'year': 2026,
  'month': 8,
  'total_cents': 0,
  'outstanding_cents': 0,
  'worked_days': 0,
  'providers': <dynamic>[],
};

http.Response _json(Object body, [int status = 200]) => http.Response(
  jsonEncode(body),
  status,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A backend whose writes hang until the test releases them, standing in for a
/// slow network.
class _SlowApi {
  _SlowApi({this.failWrites = false});

  final bool failWrites;
  final List<String> calls = [];
  final List<Completer<void>> gates = [];

  /// Entries the fake backend is holding, so a refresh after a write returns
  /// what the write actually did instead of a fixed empty list.
  final List<Map<String, dynamic>> entries = [];

  late final http.Client client = MockClient((request) async {
    final route = '${request.method} ${request.url.path}';
    calls.add(route);

    final isWrite = request.method != 'GET';
    if (isWrite) {
      final gate = Completer<void>();
      gates.add(gate);
      await gate.future;
      if (failWrites) {
        return _json({'code': 'internal_error', 'message': 'falhou'}, 500);
      }
    }

    switch (request.url.path) {
      case '/api/v1/providers':
        return _json(
          request.method == 'POST'
              ? _provider('novo', '')
              : [_provider('p1', 'Marilia')],
        );
      case '/api/v1/entries':
        if (request.method == 'GET') return _json(entries);
        if (request.method == 'DELETE') {
          final q = request.url.queryParameters;
          entries.removeWhere(
            (e) =>
                e['provider_id'] == q['provider_id'] && e['date'] == q['date'],
          );
          return http.Response('', 204);
        }
        final body = jsonDecode(request.body) as Map<String, dynamic>;
        final row = {
          'id': 'e${entries.length + 1}',
          'provider_id': body['provider_id'],
          'date': body['date'],
          'value_cents': body['value_cents'] ?? 17000,
        };
        entries
          ..removeWhere(
            (e) =>
                e['provider_id'] == row['provider_id'] &&
                e['date'] == row['date'],
          )
          ..add(row);
        return _json(row);
      default:
        return _json(_emptyMonth);
    }
  });

  /// Lets the pending write finish.
  Future<void> release() async {
    await pump();
    for (final g in gates.where((g) => !g.isCompleted)) {
      g.complete();
    }
    await pump();
  }

  int get writeCount => calls.where((c) => !c.startsWith('GET')).length;
}

/// Yields the event loop so in-flight requests actually reach the client.
/// Firing an action returns a Future immediately; the HTTP call is dispatched a
/// few microtasks later.
Future<void> pump([int turns = 8]) async {
  for (var i = 0; i < turns; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

AppState _state(_SlowApi api) => AppState(
  api: ApiClient(
    baseUrl: Uri.parse('http://test.local'),
    httpClient: api.client,
  ),
  today: DateTime(2026, 8, 12),
);

void main() {
  group('double-tap guard', () {
    test('repeated taps on "+ Nova prestadora" create only one', () async {
      final api = _SlowApi();
      final state = _state(api);
      addTearDown(state.dispose);

      // Three impatient taps while the first request is still in flight.
      final first = state.addProvider();
      state.addProvider();
      state.addProvider();
      await pump();

      expect(state.isPending(AppState.addProviderKey), isTrue);
      expect(
        api.writeCount,
        1,
        reason: 'the extra taps must not reach the server',
      );

      await api.release();
      await first;

      expect(state.isPending(AppState.addProviderKey), isFalse);
      expect(api.writeCount, 1);
    });

    test(
      'a second toggle on the same day is ignored while in flight',
      () async {
        final api = _SlowApi();
        final state = _state(api);
        addTearDown(state.dispose);
        await state.load();

        final date = DateTime(2026, 8, 5);
        final first = state.toggleEntry('p1', date);
        state.toggleEntry('p1', date);
        await pump();

        expect(state.isPending(AppState.entryKey('p1', date)), isTrue);
        expect(api.writeCount, 1);

        await api.release();
        await first;
        expect(state.isPending(AppState.entryKey('p1', date)), isFalse);
      },
    );

    test('different days are independent', () async {
      final api = _SlowApi();
      final state = _state(api);
      addTearDown(state.dispose);
      await state.load();

      state.toggleEntry('p1', DateTime(2026, 8, 5));
      state.toggleEntry('p1', DateTime(2026, 8, 6));
      await pump();

      // Marking two days quickly must not drop the second.
      expect(api.writeCount, 2);
      await api.release();
    });
  });

  group('optimistic toggle', () {
    test('the day is marked before the server answers', () async {
      final api = _SlowApi();
      final state = _state(api);
      addTearDown(state.dispose);
      await state.load();

      final date = DateTime(2026, 8, 5);
      expect(state.entryFor('p1', date), isNull);

      final pending = state.toggleEntry('p1', date);

      // This is the fix for the lag: the entry exists locally straight away,
      // with the prestadora's default rate, while the request is still open.
      final optimistic = state.entryFor('p1', date);
      expect(optimistic, isNotNull);
      expect(optimistic!.valueCents, 17000);

      await api.release();
      await pending;
      expect(state.entryFor('p1', date), isNotNull);
    });

    test('a rejected toggle is rolled back', () async {
      final api = _SlowApi(failWrites: true);
      final state = _state(api);
      addTearDown(state.dispose);
      await state.load();

      final date = DateTime(2026, 8, 5);
      final pending = state.toggleEntry('p1', date);
      expect(state.entryFor('p1', date), isNotNull, reason: 'optimistic');

      await api.release();
      await pending;

      expect(
        state.entryFor('p1', date),
        isNull,
        reason: 'the server refused, so the local mark must go away',
      );
      expect(state.toast, isNotNull, reason: 'the failure should be reported');
    });
  });

  test('marking a day does not refetch the prestadora list', () async {
    final api = _SlowApi();
    final state = _state(api);
    addTearDown(state.dispose);
    await state.load();
    api.calls.clear();

    final pending = state.toggleEntry('p1', DateTime(2026, 8, 5));
    await api.release();
    await pending;

    // Only the month is refreshed: /providers is untouched by a day change,
    // and re-fetching it just adds latency on the hot path.
    expect(api.calls, isNot(contains('GET /api/v1/providers')));
    expect(api.calls, contains('GET /api/v1/entries'));
  });
}
