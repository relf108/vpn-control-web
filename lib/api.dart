import 'dart:convert';

import 'package:http/http.dart' as http;

class ApiException implements Exception {
  ApiException(this.message, {this.unauthorized = false});
  final String message;
  final bool unauthorized;
  @override
  String toString() => message;
}

class VpnApi {
  VpnApi({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;
  String? _csrf;

  Future<Map<String, dynamic>> request(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final uri = Uri.base.resolve('/api/v1/$path');
    final headers = {
      'Accept': 'application/json',
      if (body != null) 'Content-Type': 'application/json',
      if (_csrf != null) 'X-CSRF-Token': _csrf!,
    };
    final response =
        await (body == null
                ? _client.get(uri, headers: headers)
                : _client.post(uri, headers: headers, body: jsonEncode(body)))
            .timeout(const Duration(seconds: 80));
    Map<String, dynamic> data;
    try {
      data = jsonDecode(response.body) as Map<String, dynamic>;
    } catch (_) {
      throw ApiException('API unavailable. Check the server connection.');
    }
    if (response.statusCode >= 400) {
      throw ApiException(
        data['message'] as String? ?? 'Request failed.',
        unauthorized: response.statusCode == 401,
      );
    }
    if (data['csrfToken'] is String) _csrf = data['csrfToken'] as String;
    return data;
  }

  Future<void> login(String username, String password) async {
    await request('login', body: {'username': username, 'password': password});
  }

  Future<void> logout() async {
    await request('logout', body: {});
    _csrf = null;
  }

  void close() => _client.close();
}
