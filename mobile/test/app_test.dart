import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:lynveris/api.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynveris/main.dart';
import 'package:lynveris/store.dart';

import 'store_test.dart' show MemoryStorage;
import 'store_test.dart' as fixtures;

void main() {
  testWidgets('can check another URL after returning from a result', (
    tester,
  ) async {
    final store = AppStore(MemoryStorage());
    await store.load();
    store.onboardingDone = true;
    var calls = 0;
    final api = ApiClient(
      client: MockClient((request) async {
        calls++;
        final body = fixtures.result();
        body['title'] = calls == 1 ? 'Chưa đủ thông tin' : 'Cần thận trọng';
        body['verdict'] = calls == 1 ? 'insufficient' : 'caution';
        body['url']['hostname'] = calls == 1 ? 'example.org' : 'evil.example';
        body['url']['unicode_hostname'] = body['url']['hostname'];
        return http.Response.bytes(utf8.encode(jsonEncode(body)), 200);
      }),
    );
    await tester.pumpWidget(LynverisApp(store: store, api: api));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'https://example.org');
    await tester.tap(find.text('Kiểm tra đường link'));
    await tester.pumpAndSettle();
    expect(find.text('Chưa đủ thông tin'), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byType(TextField),
      'https://google.com@evil.example/login',
    );
    await tester.tap(find.text('Kiểm tra đường link'));
    await tester.pumpAndSettle();
    expect(calls, 2);
    expect(find.text('Cần thận trọng'), findsOneWidget);
  });
  testWidgets('small screen and large text remain usable', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final store = AppStore(MemoryStorage());
    await store.load();
    store.textScale = 1.5;
    await tester.pumpWidget(LynverisApp(store: store));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Bắt đầu kiểm tra'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
  testWidgets('onboarding, navigation, empty history and settings work', (
    tester,
  ) async {
    final store = AppStore(MemoryStorage());
    await store.load();
    await tester.pumpWidget(LynverisApp(store: store));
    await tester.pumpAndSettle();
    expect(find.text('Bình tĩnh trước mỗi đường link'), findsOneWidget);
    await tester.tap(find.text('Bắt đầu kiểm tra'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    await tester.tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(find.text('Bạn quyết định điều gì được lưu'), findsOneWidget);
    await tester.tap(find.text('Cài đặt'));
    await tester.pumpAndSettle();
    expect(find.text('Quyền riêng tư'), findsWidgets);
  });
}
