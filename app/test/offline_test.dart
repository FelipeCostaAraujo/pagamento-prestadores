import 'dart:convert';

import 'package:diarias/api/api_client.dart';
import 'package:diarias/models/models.dart';
import 'package:diarias/offline/offline_store.dart';
import 'package:diarias/state/app_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> _provider(String id) => {
  'id': id,
  'name': 'Marília',
  'default_rate_cents': 17000,
  'color_index': 0,
  'position': 0,
  'phone': '',
};

http.Response _json(Object body) => http.Response(
  jsonEncode(body),
  200,
  headers: {'content-type': 'application/json; charset=utf-8'},
);

/// A backend that can be switched offline mid-test.
class _FlakyApi {
  bool online = true;
  final List<String> writes = [];

  late final http.Client client = MockClient((request) async {
    if (!online) throw http.ClientException('connection refused');

    final path = request.url.path;
    if (path == '/api/v1/entries' && request.method != 'GET') {
      writes.add('${request.method} ${request.url.queryParameters}');
      if (request.method == 'DELETE') return http.Response('', 204);
      final body = jsonDecode(request.body) as Map<String, dynamic>;
      return _json({
        'id': 'e1',
        'provider_id': body['provider_id'],
        'date': body['date'],
        'value_cents': body['value_cents'] ?? 17000,
        'kind': body['kind'] ?? 'full',
      });
    }
    return switch (path) {
      '/api/v1/providers' => _json([_provider('p1')]),
      '/api/v1/entries' => _json(<dynamic>[]),
      _ => _json({
        'year': 2026,
        'month': 8,
        'total_cents': 0,
        'outstanding_cents': 0,
        'worked_days': 0,
        'providers': <dynamic>[],
      }),
    };
  });
}

AppState _state(_FlakyApi api) => AppState(
  api: ApiClient(
    baseUrl: Uri.parse('http://test.local'),
    httpClient: api.client,
  ),
  today: DateTime(2026, 8, 12),
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues(<String, Object>{}));

  test('a month seen once is still readable offline', () async {
    final api = _FlakyApi();
    final state = _state(api);
    addTearDown(state.dispose);

    await state.load();
    expect(state.providers, hasLength(1));
    expect(state.offlineMode, isFalse);

    // Same month, now with no connection: the app falls back to what it saw.
    final offline = _state(api..online = false);
    addTearDown(offline.dispose);
    await offline.load();

    expect(offline.offlineMode, isTrue);
    expect(offline.error, isNull, reason: 'cached data is not an error state');
    expect(offline.providers, hasLength(1));
    expect(offline.cachedAt, isNotNull);
  });

  test('with no cache at all, offline is still an error', () async {
    final api = _FlakyApi()..online = false;
    final state = _state(api);
    addTearDown(state.dispose);

    await state.load();

    // Nothing to show: the retry screen is the honest answer here.
    expect(state.offlineMode, isFalse);
    expect(state.error, isNotNull);
  });

  test('a day marked offline is kept and replayed later', () async {
    final api = _FlakyApi();
    final state = _state(api);
    addTearDown(state.dispose);
    await state.load();

    api.online = false;
    final date = DateTime(2026, 8, 5);
    await state.toggleEntry('p1', date);

    // The mark stays on screen and is remembered rather than rolled back.
    expect(state.entryFor('p1', date), isNotNull);
    expect(state.queuedWrites, 1);
    expect(await OfflineStore().readQueue(), hasLength(1));

    // Connection is back.
    api.online = true;
    api.writes.clear();
    await state.load();

    expect(api.writes, hasLength(1), reason: 'the queued write was replayed');
    expect(state.queuedWrites, 0);
    expect(state.offlineMode, isFalse);
  });

  test(
    'repeated offline edits to one day collapse into a single write',
    () async {
      final api = _FlakyApi();
      final state = _state(api);
      addTearDown(state.dispose);
      await state.load();

      api.online = false;
      final date = DateTime(2026, 8, 5);
      // Marked, changed to half, changed to absence — one day, one outcome.
      await state.toggleEntry('p1', date);
      await state.setEntryKind('p1', date, EntryKind.half);
      await state.setEntryKind('p1', date, EntryKind.absence);

      expect(
        state.queuedWrites,
        1,
        reason: 'replaying every intermediate state would be pointless traffic',
      );
      final queued = (await OfflineStore().readQueue()).single;
      expect(queued.kind, EntryKind.absence, reason: 'the last edit wins');
    },
  );

  test('a queued write survives the app being restarted', () async {
    final api = _FlakyApi();
    final first = _state(api);
    await first.load();
    api.online = false;
    await first.toggleEntry('p1', DateTime(2026, 8, 5));
    first.dispose();

    // A fresh AppState, as after the process was killed.
    api.online = true;
    api.writes.clear();
    final second = _state(api);
    addTearDown(second.dispose);
    await second.load();

    expect(api.writes, hasLength(1));
    expect(second.queuedWrites, 0);
  });
}
