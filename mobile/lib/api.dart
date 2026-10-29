import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'store.dart';

class ApiFailure implements Exception {
  const ApiFailure(this.message);
  final String message;
  @override
  String toString() => message;
}

class ApiClient {
  ApiClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;
  Uri endpoint(String base, String path) {
    final uri = Uri.tryParse(base);
    if (uri == null ||
        !['http', 'https'].contains(uri.scheme) ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
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
    if (uri.scheme != 'https' && !development) {
      throw const ApiFailure(
        'Hãy dùng HTTPS cho máy chủ ngoài máy phát triển.',
      );
    }
    return Uri.parse('${base.replaceAll(RegExp(r'/+$'), '')}$path');
  }

  Future<Map<String, dynamic>> check(String url, AppStore store) async {
    try {
      final response = await _client
          .post(
            endpoint(store.apiBase, '/v1/check'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'url': url,
              'use_threat_intelligence': store.useThreat,
              'research_consent': store.researchConsent,
              if (store.researchConsent) 'deletion_token': store.deletionToken,
            }),
          )
          .timeout(const Duration(seconds: 15));
      final body = jsonDecode(utf8.decode(response.bodyBytes));
      if (response.statusCode != 200) {
        throw ApiFailure(
          body is Map && body['detail'] is String
              ? body['detail']
              : 'Máy chủ chưa xử lý được. Vui lòng thử lại.',
        );
      }
      if (body is! Map<String, dynamic> ||
          body['url'] is! Map ||
          body['verdict'] is! String) {
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
      final response = await _client
          .delete(
            endpoint(store.apiBase, '/v1/research'),
            headers: {'X-Deletion-Token': store.deletionToken},
          )
          .timeout(const Duration(seconds: 15));
      if (response.statusCode != 200) {
        throw const ApiFailure(
          'Chưa xoá được thống kê trên máy chủ. Hãy thử lại khi có mạng.',
        );
      }
      return (jsonDecode(response.body) as Map)['deleted'] as int;
    } on TimeoutException {
      throw const ApiFailure('Xoá thống kê quá thời gian chờ. Hãy thử lại.');
    } on http.ClientException {
      throw const ApiFailure(
        'Chưa kết nối được để xoá thống kê. Hãy thử lại khi có mạng.',
      );
    }
  }
}
