import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:lynveris/api.dart';
import 'package:lynveris/main.dart';
import 'package:lynveris/store.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('URL report and recovery against the local live APIs', (
    tester,
  ) async {
    const bridge = MethodChannel('vn.lynveris/share');
    expect(
      await bridge.invokeMethod<String>('getPackageName'),
      'vn.lynveris.lynveris.qa',
    );

    final store = AppStore(DeviceStorage());
    await store.load();
    store.onboardingDone = true;
    store.useThreat = true;
    store.saveHistory = true;
    store.researchConsent = false;
    const apiBase = 'http://10.0.2.2:8000';
    await store.setServer(apiBase);
    await store.clearHistory();
    final api = ApiClient();
    addTearDown(api.close);
    tester.testTextInput.register();
    addTearDown(tester.testTextInput.unregister);

    Future<void> waitFor(Finder finder) async {
      final deadline = DateTime.now().add(const Duration(seconds: 25));
      while (finder.evaluate().isEmpty && DateTime.now().isBefore(deadline)) {
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      expect(finder, findsWidgets);
      await tester.pumpAndSettle();
    }

    final viewport = GlobalKey();
    final screenshots = <Map<String, Object>>[];
    binding.reportData = {'screenshots': screenshots};
    Future<void> capture(String name) async {
      final boundary =
          viewport.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(
        pixelRatio: tester.view.devicePixelRatio,
      );
      try {
        final png = await image.toByteData(format: ui.ImageByteFormat.png);
        screenshots.add({
          'screenshotName': name,
          'bytes': png!.buffer.asUint8List(),
        });
      } finally {
        image.dispose();
      }
    }

    Future<void> tap(Finder finder) async {
      await tester.ensureVisible(finder.first);
      await tester.tap(finder.first);
      await tester.pump();
    }

    final input = find.byType(TextField);
    final start = find.text('Kiểm tra đường link');
    Future<void> enter(String text) async {
      await tester.ensureVisible(input);
      await tester.enterText(input, text);
      await tester.pumpAndSettle();
      expect(tester.widget<TextField>(input).controller!.text, text);
    }

    Future<void> check(String url, String label) async {
      await enter(url);
      await tap(start);
      await waitFor(find.text(label));
    }

    Future<void> back() async {
      await tap(find.byType(BackButton));
      await tester.pumpAndSettle();
    }

    await tester.pumpWidget(
      RepaintBoundary(
        key: viewport,
        child: LynverisApp(store: store, api: api),
      ),
    );
    await tester.pumpAndSettle();
    await capture('01-nhap-link');
    await tap(start);
    expect(
      find.text('Hãy nhập hoặc dán đường link cần kiểm tra.'),
      findsOneWidget,
    );
    await enter('không có link');
    await tap(start);
    expect(
      find.textContaining('Chưa tìm thấy đường link hợp lệ'),
      findsOneWidget,
    );

    const academy = 'https://awsacademy.instructure.com/';
    await enter('AWS Academy $academy hoặc https://example.org/');
    await tap(start);
    await waitFor(find.text('Chọn đường link cần kiểm tra'));
    await tap(find.text('awsacademy.instructure.com'));
    await waitFor(find.text('Chưa phát hiện dấu hiệu đáng ngờ'));
    expect(find.text('instructure.com', findRichText: true), findsOneWidget);
    await capture('02-link-binh-thuong');
    await tap(find.text('Xem bằng chứng'));
    await tester.pumpAndSettle();
    expect(find.text('Google Safe Browsing'), findsOneWidget);
    expect(find.text('OpenPhish Community'), findsOneWidget);
    expect(find.text('Chưa ghi nhận'), findsNWidgets(2));
    await capture('03-bang-chung');
    await back();

    await check('https://paypal.com@verify.example.org/login', 'Cần xác minh');
    await capture('04-can-xac-minh');
    await tap(find.text('Xem dấu hiệu'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Máy chủ thực tế nằm sau dấu @'),
      findsOneWidget,
    );
    expect(find.text('/login', findRichText: true), findsOneWidget);
    await capture('05-cau-truc-url');
    await back();

    await check(
      'https://testsafebrowsing.appspot.com/s/phishing.html',
      'Nguy cơ cao',
    );
    expect(
      find.textContaining('Google Safe Browsing đã ghi nhận'),
      findsOneWidget,
    );
    expect(find.text('Chia sẻ cảnh báo'), findsOneWidget);
    await capture('06-nguy-co-cao');
    await back();

    await check('https://bit.ly/lynveris-example', 'Cần xác minh');
    expect(find.textContaining('Chưa xác minh địa chỉ đích'), findsOneWidget);
    await back();

    await tap(find.text('Lịch sử'));
    await tester.pumpAndSettle();
    expect(store.history.length, 4);
    await capture('07-lich-su');
    await tap(find.text('awsacademy.instructure.com'));
    await waitFor(find.text('Kết quả lần trước'));
    await tap(find.text('Nhập lại URL gốc'));
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(input).controller!.text, isEmpty);

    await store.setServer('http://10.0.2.2:8003');
    await check(academy, 'Chưa đủ thông tin');
    expect(find.text('Chưa tra được · Nguồn chưa cấu hình'), findsOneWidget);
    await capture('08-nguon-chua-day-du');
    await store.setServer(apiBase);
    await tap(find.text('Thử lại'));
    await waitFor(find.text('Chưa phát hiện dấu hiệu đáng ngờ'));
    await back();

    await store.setServer('http://10.0.2.2:8002');
    await enter(academy);
    await tap(start);
    await waitFor(find.textContaining('Không kết nối được máy chủ.'));
    expect(tester.widget<TextField>(input).controller!.text, academy);
    await store.setServer('http://10.0.2.2:8001');
    await tap(find.text('Thử lại'));
    await waitFor(find.textContaining('Máy chủ phản hồi quá lâu.'));
    await capture('09-thu-lai');
    await store.setServer(apiBase);
    await tap(find.text('Thử lại'));
    await waitFor(find.text('Chưa phát hiện dấu hiệu đáng ngờ'));
  });
}
