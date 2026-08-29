import 'package:diarias/api/api_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('defaults to the deployed API over HTTPS', () {
    final url = ApiClient.defaultBaseUrl();

    expect(url.toString(), 'https://colaboradores.fca.dev.br');
    // The login posts a password; plain HTTP would put it on the wire.
    expect(url.scheme, 'https');
  });

  test('a client built with no arguments targets production', () {
    final client = ApiClient();
    addTearDown(client.dispose);

    expect(client.baseUrl.host, 'colaboradores.fca.dev.br');
  });

  test('an explicit baseUrl still wins, for local development', () {
    final client = ApiClient(baseUrl: Uri.parse('http://192.168.10.180:7000'));
    addTearDown(client.dispose);

    expect(client.baseUrl.toString(), 'http://192.168.10.180:7000');
  });

  test('identifies the device so the session list is readable', () {
    // Every row used to read "Aplicativo" because the http package sends the
    // same agent everywhere, which defeated the connected-devices screen.
    for (final ua in [
      'Diarias/1.0.0 (Android)',
      'Diarias/1.0.0 (iPhone)',
      'Diarias/1.0.0 (Mac)',
    ]) {
      final session = SessionInfo(
        id: 's1',
        userAgent: ua,
        createdAt: DateTime(2026, 8, 1),
        lastSeenAt: DateTime(2026, 8, 1),
        current: false,
      );
      expect(session.label, isNot('Aparelho desconhecido'));
      expect(session.label, isNot(contains('Diarias')));
    }
  });

  test(
    'a session from before the app identified itself is labelled as old',
    () {
      final session = SessionInfo(
        id: 's1',
        userAgent: 'Dart/3.12 (dart:io)',
        createdAt: DateTime(2026, 8, 1),
        lastSeenAt: DateTime(2026, 8, 1),
        current: false,
      );
      expect(session.label, 'Aparelho antigo');
    },
  );
}
