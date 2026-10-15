import 'dart:convert';

import 'package:http/http.dart' as http;

class AnamneApiException implements Exception {
  AnamneApiException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  bool get isAuth => statusCode == 401 || statusCode == 403;

  @override
  String toString() => message;
}

/// Thin REST client for the self-hosted Anamne API.
class AnamneApi {
  AnamneApi({required String baseUrl, required this.token, http.Client? client})
      : baseUrl = baseUrl.endsWith('/')
            ? baseUrl.substring(0, baseUrl.length - 1)
            : baseUrl,
        _client = client ?? http.Client();

  final String baseUrl;
  final String token;
  final http.Client _client;

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Future<Map<String, Object?>> _send(Future<http.Response> future) async {
    final response = await future.timeout(const Duration(seconds: 20));
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Object?;
    if (response.statusCode >= 400) {
      final message = body is Map && body['error'] is String
          ? body['error'] as String
          : 'HTTP ${response.statusCode}';
      throw AnamneApiException(message, statusCode: response.statusCode);
    }
    return body is Map<String, Object?> ? body : <String, Object?>{};
  }

  Future<Map<String, Object?>> health() =>
      _send(_client.get(Uri.parse('$baseUrl/v1/health'), headers: _headers));

  Future<Map<String, Object?>> pull({required int cursor, int limit = 200}) =>
      _send(_client.get(
        Uri.parse('$baseUrl/v1/sync/pull?cursor=$cursor&limit=$limit'),
        headers: _headers,
      ));

  Future<Map<String, Object?>> push(List<Map<String, Object?>> ops) =>
      _send(_client.post(Uri.parse('$baseUrl/v1/sync/push'),
          headers: _headers, body: jsonEncode({'ops': ops})));

  void close() => _client.close();
}
