// Real Flutter -> live FastAPI -> result. Run on Android emulator, no provider mock.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lynveris/main.dart';
import 'package:lynveris/store.dart';
import 'package:lynveris/api.dart';

class ObservedLiveApi extends ApiClient {
  final requests = <String>[];
  @override
  Future<Map<String, dynamic>> check(String url, AppStore store) async {
    requests.add(url);
    return super.check(url, store);
  }
}

class EphemeralStorage implements KeyValueStorage {
  final values = <String, String>{};
  @override
  Future<String?> read(String key) async => values[key];
  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }
}

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Future<void> capture(String name) async {
    final bytes = await binding.takeScreenshot(name);
    await File('${Directory.systemTemp.path}/$name.png').writeAsBytes(bytes);
  }

  testWidgets(
    'real backend returns honest insufficient result and actual hostname',
    (tester) async {
      final store = AppStore(EphemeralStorage());
      await store.load();
      store.onboardingDone = true;
      store.apiBase = const String.fromEnvironment(
        'API_BASE_URL',
        defaultValue: 'http://10.0.2.2:8000',
      );
      final liveApi = ObservedLiveApi();
      await tester.pumpWidget(LynverisApp(store: store, api: liveApi));
      await tester.pumpAndSettle();
      if (const bool.fromEnvironment('CAPTURE_QA')) {
        await binding.convertFlutterSurfaceToImage();
        await tester.pumpAndSettle();
        await capture('lynveris-home');
      }
      await tester.enterText(find.byType(TextField), 'https://example.org/');
      final button = find.text('Kiểm tra đường link');
      await tester.ensureVisible(button);
      await tester.tap(button);
      // pumpAndSettle alone does not wait for external HTTP response.
      for (
        var i = 0;
        i < 150 && find.text('example.org').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      expect(find.text('Kết quả kiểm tra'), findsOneWidget);
      expect(find.text('Chưa đủ thông tin'), findsOneWidget);
      expect(find.text('example.org'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_QA')) {
        await capture('lynveris-insufficient');
      }
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(find.byType(TextField)).enabled, isTrue);
      await tester.enterText(
        find.byType(TextField),
        'https://google.com@evil.example/login',
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(find.byType(TextField)).controller!.text,
        'https://google.com@evil.example/login',
      );
      await tester.ensureVisible(find.text('Kiểm tra đường link'));
      final checkButton = find.ancestor(
        of: find.text('Kiểm tra đường link'),
        matching: find.byType(FilledButton),
      );
      expect(tester.widget<FilledButton>(checkButton).onPressed, isNotNull);
      await tester.tap(find.text('Kiểm tra đường link'));
      for (
        var i = 0;
        i < 150 && find.text('evil.example').evaluate().isEmpty;
        i++
      ) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
        await tester.pump();
      }
      await tester.pumpAndSettle();
      expect(liveApi.requests, [
        'https://example.org/',
        'https://google.com@evil.example/login',
      ]);
      if (const bool.fromEnvironment('CAPTURE_QA')) {
        await capture('lynveris-warning');
      }
      expect(find.text('Cần thận trọng'), findsOneWidget);
      expect(find.text('evil.example'), findsOneWidget);
      if (const bool.fromEnvironment('CAPTURE_QA')) {
        final ready = File('${Directory.systemTemp.path}/qa-ready');
        final collected = File('${Directory.systemTemp.path}/qa-collected');
        await ready.writeAsString('ready');
        for (var i = 0; i < 1200 && !await collected.exists(); i++) {
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
        expect(
          await collected.exists(),
          isTrue,
          reason: 'Run scripts/collect_test_screenshots.py while the capture test is active.',
        );
      }
    },
  );
}
