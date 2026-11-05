import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lynveris/api.dart';
import 'package:lynveris/store.dart';

import 'store_test.dart' show MemoryStorage, result;

void main() {
  test(
    'request sends selected URL only, no message and no consent by default',
    () async {
      final store = AppStore(MemoryStorage());
      await store.load();
      final api = ApiClient(
        client: MockClient((r) async {
          final body = jsonDecode(r.body) as Map;
          expect(body['url'], 'https://example.org');
          expect(body.containsKey('message'), isFalse);
          expect(body['research_consent'], isFalse);
          expect(body['use_threat_intelligence'], isFalse);
          return http.Response.bytes(utf8.encode(jsonEncode(result())), 200);
        }),
      );
      expect(
        (await api.check('https://example.org', store))['verdict'],
        'insufficient',
      );
    },
  );
  test('timeout/source errors never become safe results', () async {
    final store = AppStore(MemoryStorage());
    await store.load();
    final api = ApiClient(
      client: MockClient(
        (r) async =>
            http.Response.bytes(utf8.encode('{"detail":"Giới hạn lượt"}'), 429),
      ),
    );
    await expectLater(
      api.check('https://example.com', store),
      throwsA(isA<ApiFailure>()),
    );
    final offline = ApiClient(
      client: MockClient((r) async => throw http.ClientException('offline')),
    );
    await expectLater(
      offline.check('https://example.com', store),
      throwsA(isA<ApiFailure>()),
    );
  });
  test('requires encrypted production API and preserves development route', () {
    final api = ApiClient();
    expect(
      () => api.endpoint('http://public.example', '/health'),
      throwsA(isA<ApiFailure>()),
    );
    expect(api.endpoint('http://10.0.2.2:8000', '/v1/check').host, '10.0.2.2');
    final release = ApiClient(allowLocalHttp: false);
    expect(
      () => release.endpoint('http://10.0.2.2:8000', '/health'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test('server setup verifies Lynveris without following redirects', () async {
    final api = ApiClient(
      client: MockClient((request) async {
        expect(request.followRedirects, isFalse);
        expect(request.method, 'GET');
        expect(request.url.path, '/health');
        if (request.url.host == 'lynveris.example') {
          return http.Response('{"status":"ok","service":"lynveris"}', 200);
        }
        return http.Response(
          '',
          307,
          headers: {'location': 'https://lynveris.example/health'},
        );
      }),
    );
    await api.verifyServer('https://lynveris.example/');
    await expectLater(
      api.verifyServer('https://redirect.example'),
      throwsA(isA<ApiFailure>()),
    );
  });

  test(
    'partial response cannot navigate to a result or enter history',
    () async {
      final store = AppStore(MemoryStorage());
      await store.load();
      final api = ApiClient(
        client: MockClient((request) async {
          expect(request.followRedirects, isFalse);
          return http.Response(
            '{"url":{"hostname":"example.org"},"verdict":"no_signs"}',
            200,
          );
        }),
      );
      await expectLater(
        api.check('https://example.org', store),
        throwsA(isA<ApiFailure>()),
      );
    },
  );
}
