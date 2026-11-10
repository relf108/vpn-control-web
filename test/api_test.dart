import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vpn_control_web/api.dart';

void main() {
  test('login keeps CSRF in memory and sends it with writes', () async {
    final requests = <http.Request>[];
    final api = VpnApi(
      client: MockClient((request) async {
        requests.add(request);
        return http.Response(jsonEncode({'csrfToken': 'test-token'}), 200);
      }),
    );
    await api.login('operator', 'synthetic-password');
    await api.request('restore', body: {'targets': 'all'});
    expect(requests.first.url.path, '/api/v1/login');
    expect(requests.last.headers['X-CSRF-Token'], 'test-token');
    expect(jsonDecode(requests.last.body), {'targets': 'all'});
    api.close();
  });

  test('unauthorized response is distinct from controller failure', () async {
    final api = VpnApi(
      client: MockClient((_) async {
        return http.Response('{"message":"Sign in required."}', 401);
      }),
    );
    await expectLater(
      api.request('status'),
      throwsA(isA<ApiException>().having((e) => e.unauthorized, 'auth', true)),
    );
    api.close();
  });

  test('proxy errors do not display HTML as status', () async {
    final api = VpnApi(
      client: MockClient((_) async {
        return http.Response('<html>Bad gateway</html>', 502);
      }),
    );
    await expectLater(api.request('status'), throwsA(isA<ApiException>()));
    api.close();
  });
}
