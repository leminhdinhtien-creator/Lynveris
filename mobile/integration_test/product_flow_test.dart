// Real Android -> Windows FastAPI -> PostgreSQL. No detection/provider mock.
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lynveris/api.dart';
import 'package:lynveris/main.dart';
import 'package:lynveris/store.dart';

class LiveApi extends ApiClient {
  final results = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> check(String url, AppStore store) async {
    final result = await super.check(url, store);
    results.add(result);
    return result;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  final screenshots = <String>[];
  Future<void> capture(String name) async {
    final bytes = await binding.takeScreenshot(name);
    await File('${Directory.systemTemp.path}/$name.png').writeAsBytes(bytes);
    screenshots.add(name);
  }

  testWidgets(
    'live product, source, persistence, PostgreSQL and network failures',
    (tester) async {
      final package = await const MethodChannel('vn.lynveris/share')
          .invokeMethod<String>('getPackageName');
      expect(
        package,
        'vn.lynveris.lynveris.qa',
        reason: 'Abort before accessing user preferences unless this is the isolated QA app.',
      );
      Future<void> waitFor(
        bool Function() condition, {
        int seconds = 25,
      }) async {
        final end = DateTime.now().add(Duration(seconds: seconds));
        while (!condition() && DateTime.now().isBefore(end)) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
          await tester.pump();
        }
        expect(condition(), isTrue);
        await tester.pumpAndSettle();
      }

      Future<void> tapText(String text) async {
        await tester.ensureVisible(find.text(text).last);
        await tester.tap(find.text(text).last);
        await tester.pumpAndSettle();
      }

      final store = AppStore(DeviceStorage());
      await store.load();
      store.onboardingDone = true;
      store.saveHistory = true;
      store.useThreat = true;
      store.researchConsent = true;
      store.apiBase = 'http://10.0.2.2:8000';
      await store.persist();
      final api = LiveApi();
      addTearDown(() async {
        // This is the verified QA package's own token, never the user's main app.
        store.apiBase = 'http://10.0.2.2:8000';
        try {
          await api.deleteResearch(store);
        } catch (_) {
          // Keep the original failure; server outage cannot be reported as successful cleanup.
        }
      });
      await tester.pumpWidget(LynverisApp(store: store, api: api));
      await tester.pumpAndSettle();
      await binding.convertFlutterSurfaceToImage();
      await tester.pumpAndSettle();
      await capture('lynveris-home');

      Future<void> check(String url, int expectedResults) async {
        await tester.enterText(find.byType(TextField), url);
        await tester.ensureVisible(find.text('Kiểm tra đường link'));
        await tester.tap(find.text('Kiểm tra đường link'));
        await waitFor(
          () =>
              api.results.length == expectedResults &&
              find.byType(ResultPage).evaluate().isNotEmpty,
        );
      }

      await check('https://example.org/?private=qa-only', 1);
      expect(api.results.last['model']['status'], 'ready');
      expect(find.text(api.results.last['title']), findsOneWidget);
      expect(api.results.last['threat']['status'], 'not_found');
      expect(api.results.last['threat']['checks'].length, 2);
      await capture('lynveris-model-result');
      await tapText('Nguồn và giới hạn kiểm tra');
      expect(find.textContaining('OpenPhish Community:'), findsWidgets);
      expect(find.textContaining('Google Safe Browsing:'), findsWidgets);
      expect(
        find.text('Mô hình: ${api.results.last['model']['version']}'),
        findsOneWidget,
      );
      await capture('lynveris-details');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      await check('https://google.com@evil.example/login', 2);
      expect(find.text('Cần thận trọng'), findsOneWidget);
      expect(find.text('evil.example'), findsOneWidget);
      await capture('lynveris-warning');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      const feedUrl = String.fromEnvironment('LIVE_FEED_URL');
      expect(
        feedUrl,
        isNotEmpty,
        reason: 'Use a URL from the currently downloaded real feed.',
      );
      await check(feedUrl, 3);
      expect(api.results.last['threat']['status'], 'detected');
      expect(find.text('Nguy cơ cao'), findsOneWidget);
      await capture('lynveris-live-threat');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tapText('Lịch sử');
      expect(store.history.length, 3);
      final restored = AppStore(DeviceStorage());
      await restored.load();
      expect(restored.history.length, 3);
      expect(jsonEncode(restored.history), isNot(contains('private=qa-only')));
      await capture('lynveris-history');
      await tapText('example.org');
      expect(find.text('Kết quả đã lưu'), findsOneWidget);
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Xoá kết quả').first);
      await tester.pumpAndSettle();
      expect(store.history.length, 2);
      await tapText('Xoá tất cả');
      await tapText('Xoá');
      expect(store.history, isEmpty);

      // Actual secondary API: Google deliberately unconfigured; OpenPhish remains live.
      await tapText('Kiểm tra');
      store.apiBase = 'http://10.0.2.2:8003';
      store.researchConsent = false;
      store.saveHistory = false;
      await check('https://example.org/', 4);
      expect(api.results.last['threat']['partial'], isTrue);
      expect(
        api.results.last['threat']['checks'][0]['status'],
        'not_configured',
      );
      await tapText('Nguồn và giới hạn kiểm tra');
      await capture('lynveris-source-unavailable');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();

      // These are real TCP failure paths: closed port and a socket which accepts but never replies.
      await tapText('Kiểm tra');
      store.apiBase = 'http://10.0.2.2:8002';
      await tester.enterText(find.byType(TextField), 'https://example.org/');
      await tester.tap(find.text('Kiểm tra đường link'));
      await waitFor(
        () => find
            .textContaining('Không kết nối được máy chủ.')
            .evaluate()
            .isNotEmpty,
      );
      await capture('lynveris-offline');
      store.apiBase = 'http://10.0.2.2:8001';
      await tester.tap(find.text('Kiểm tra đường link'));
      await waitFor(
        () => find
            .textContaining('Máy chủ phản hồi quá lâu.')
            .evaluate()
            .isNotEmpty,
      );
      await capture('lynveris-timeout');
      expect(api.results.length, 4);
      store.apiBase = 'http://10.0.2.2:8000';
      await tapText('Cài đặt');
      await capture('lynveris-settings');
      // Collector independently reads these exact result IDs from real PostgreSQL before deletion.
      await File('${Directory.systemTemp.path}/qa-proof.json').writeAsString(
        jsonEncode({
          'ids': api.results.take(3).map((e) => e['id']).toList(),
          'model': api.results.first['model']['version'],
          'source': api.results.first['threat']['source'],
          'screenshots': screenshots,
        }),
      );
      await File('${Directory.systemTemp.path}/qa-ready')
          .writeAsString('ready');
      await waitFor(
        () => File('${Directory.systemTemp.path}/qa-collected').existsSync(),
        seconds: 120,
      );
      await tapText('Xoá thống kê trên máy chủ');
      await waitFor(
        () => find
            .text('Đã xoá thống kê gắn với thiết bị này trên máy chủ.')
            .evaluate()
            .isNotEmpty,
      );
      await File('${Directory.systemTemp.path}/qa-erased')
          .writeAsString('erased');
      await waitFor(
        () => File('${Directory.systemTemp.path}/qa-verified').existsSync(),
        seconds: 60,
      );
    },
  );
}
