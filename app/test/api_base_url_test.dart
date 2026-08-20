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
}
