import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import 'build_config.dart';
import 'store.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client, bool? allowLocalHttp})
    : _client = client ?? http.Client(),
      _allowLocalHttp = allowLocalHttp ?? allowDevelopmentHttp;

  final http.Client _client;
  final bool _allowLocalHttp;

  void close() => _client.close();

  Uri endpoint(String base, String path) {
    if (base.trim().isEmpty) {
      throw const ApiFailure('Hãy thiết lập kết nối máy chủ trong Cài đặt.');
    }
    final uri = Uri.tryParse(base.trim());
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.authority.contains('@') ||
        uri.hasQuery ||
        uri.hasFragment) {
      throw const ApiFailure(
        'Địa chỉ máy chủ không hợp lệ. Kiểm tra trong Cài đặt.',
      );
    }
    final development = [
      'localhost',
      '127.0.0.1',
      '10.0.2.2',
    ].contains(uri.host);
    if (uri.scheme != 'https' && !(_allowLocalHttp && development)) {
      throw const ApiFailure('Địa chỉ máy chủ cần bắt đầu bằng https://.');
    }
    return uri.replace(path: uri.path.replaceAll(RegExp(r'/+$'), '') + path);
  }

  Future<http.Response> _send(http.Request request) async {
    // Never resend URLs or deletion tokens to a redirect target.
    request.followRedirects = false;
    final response = await _client.send(request);
    final bytes = BytesBuilder(copy: false);
    await for (final chunk in response.stream) {
      if (bytes.length + chunk.length > 256 * 1024) {
        throw const ApiFailure('Máy chủ trả dữ liệu quá lớn.');
      }
      bytes.add(chunk);
    }
    return http.Response.bytes(bytes.takeBytes(), response.statusCode);
  }

  Future<void> verifyServer(String base) async {
    final uri = endpoint(base, '/health');
    try {
      final response = await _send(http.Request('GET', uri))
          .timeout(const Duration(seconds: 8));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode == 200 &&
          body is Map &&
          body['status'] == 'ok' &&
          body['service'] == 'lynveris') {
        return;
      }
    } on TimeoutException {
      throw const ApiFailure('Máy chủ phản hồi quá lâu. Vui lòng thử lại.');
    } on http.ClientException {
      throw const ApiFailure(
        'Không kết nối được. Hãy kiểm tra mạng và địa chỉ.',
      );
    } on FormatException {
      // A web page or malformed response is not a Lynveris API.
    }
    throw const ApiFailure('Địa chỉ này chưa trả lời như máy chủ Lynveris.');
  }

  Future<Map<String, dynamic>> check(String url, AppStore store) async {
    try {
      final request = http.Request('POST', endpoint(store.apiBase, '/v1/check'))
        ..encoding = utf8
        ..headers['Content-Type'] = 'application/json'
        ..body = jsonEncode({
          'url': url,
          'use_threat_intelligence': store.useThreat,
          'research_consent': store.researchConsent,
          if (store.researchConsent) 'deletion_token': store.deletionToken,
        });
      final response = await _send(request)
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw ApiFailure(
          body is Map && body['detail'] is String
              ? body['detail']
              : 'Máy chủ chưa xử lý được. Vui lòng thử lại.',
        );
      }
      if (body is! Map<String, dynamic> || !_validResult(body)) {
        throw const ApiFailure(
          'Kết quả máy chủ không hợp lệ. Chưa thể kết luận.',
        );
      }
      return body;
    } on TimeoutException {
      throw const ApiFailure(
        'Máy chủ phản hồi quá lâu. Chưa có kết quả kiểm tra; vui lòng thử lại.',
      );
    } on http.ClientException {
      throw const ApiFailure(
        'Không kết nối được máy chủ. Kiểm tra mạng và địa chỉ API trong Cài đặt. Chưa thực hiện kiểm tra.',
      );
    } on FormatException {
      throw const ApiFailure(
        'Máy chủ trả dữ liệu không hợp lệ. Chưa thể kết luận.',
      );
    }
  }

  Future<int> deleteResearch(AppStore store) async {
    try {
      final request = http.Request(
        'DELETE',
        endpoint(store.apiBase, '/v1/research'),
      )..headers['X-Deletion-Token'] = store.deletionToken;
      final response = await _send(request)
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200 ||
          body is! Map ||
          body['deleted'] is! int) {
        throw const ApiFailure(
          'Chưa xoá được thống kê trên máy chủ. Hãy thử lại khi có mạng.',
        );
      }
      return body['deleted'] as int;
    } on TimeoutException {
      throw const ApiFailure('Xoá thống kê quá thời gian chờ. Hãy thử lại.');
    } on http.ClientException {
      throw const ApiFailure(
        'Chưa kết nối được để xoá thống kê. Hãy thử lại khi có mạng.',
      );
    } on FormatException {
      throw const ApiFailure('Máy chủ chưa xác nhận xoá thống kê.');
    }
  }
}

bool _validResult(Map<String, dynamic> result) {
  final url = result['url'];
  final model = result['model'];
  final threat = result['threat'];
  final signals = result['signals'];
  final checks = threat is Map ? threat['checks'] : null;
  return [
        'id',
        'title',
        'summary',
        'checked_at',
      ].every((key) => result[key] is String) &&
      const {
        'high',
        'caution',
        'no_signs',
        'insufficient',
      }.contains(result['verdict']) &&
      url is Map &&
      [
        'hostname',
        'unicode_hostname',
        'scheme',
        'original',
      ].every((key) => url[key] is String) &&
      model is Map &&
      model['status'] is String &&
      (model['score'] == null || model['score'] is num) &&
      threat is Map &&
      threat['source'] is String &&
      threat['status'] is String &&
      (threat['expires_at'] == null || threat['expires_at'] is String) &&
      (threat['attribution'] == null || threat['attribution'] is String) &&
      (checks == null ||
          (checks is List && checks.every((check) => check is Map))) &&
      signals is List &&
      signals.every(
        (s) =>
            s is Map &&
            [
              'source',
              'title',
              'detail',
              'severity',
            ].every((key) => s[key] is String),
      ) &&
      ['actions', 'limitations'].every(
        (key) =>
            result[key] is List &&
            (result[key] as List).every((value) => value is String),
      );
}
