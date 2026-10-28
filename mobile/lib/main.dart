import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';

import 'api.dart';
import 'store.dart';
import 'url_input.dart';

const ink = Color(0xFF162D35),
    teal = Color(0xFF126B58),
    paper = Color(0xFFF6F8F6),
    muted = Color(0xFF566C70);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(DeviceStorage());
  await store.load();
  runApp(LynverisApp(store: store));
}

class LynverisApp extends StatelessWidget {
  const LynverisApp({super.key, required this.store, this.api});
  final AppStore store;
  final ApiClient? api;
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'Lynveris',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: paper,
        colorScheme: ColorScheme.fromSeed(
          seedColor: teal,
          primary: teal,
          surface: Colors.white,
          onSurface: ink,
        ),
        textTheme: ThemeData.light().textTheme.apply(
          bodyColor: ink,
          displayColor: ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: paper,
          foregroundColor: ink,
          elevation: 0,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 56),
            textStyle: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7F9F8),
          contentPadding: const EdgeInsets.all(20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD8E3DE)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(16),
            borderSide: const BorderSide(color: Color(0xFFD8E3DE)),
          ),
        ),
        dividerColor: const Color(0xFFE3EAE6),
      ),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: store.textScale),
        ),
        child: child!,
      ),
      home: AppShell(store: store, api: api ?? ApiClient()),
    ),
  );
}

class Brand extends StatelessWidget {
  const Brand({super.key});
  @override
  Widget build(BuildContext context) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: teal,
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.shield_outlined, color: Colors.white, size: 28),
      ),
      const SizedBox(width: 12),
      const Flexible(
        child: FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            'Lynveris',
            style: TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.w800,
              letterSpacing: -1,
            ),
          ),
        ),
      ),
    ],
  );
}

class AppShell extends StatefulWidget {
  const AppShell({super.key, required this.store, required this.api});
  final AppStore store;
  final ApiClient api;
  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _page = 0;
  final _input = TextEditingController();
  final _channel = const MethodChannel('vn.lynveris/share');
  bool _busy = false;
  String? _error;
  AppStore get store => widget.store;
  @override
  void initState() {
    super.initState();
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'sharedText' && call.arguments is String) {
        _receive(call.arguments as String);
      }
    });
    _initialShare();
  }

  Future<void> _initialShare() async {
    try {
      final text = await _channel.invokeMethod<String>('getInitialText');
      if (text != null && mounted) {
        _receive(text);
      }
    } on MissingPluginException {
      /* Android-only intent bridge. */
    }
  }

  void _receive(String text) {
    if (mounted) {
      setState(() {
        _input.text = text.length <= 12000 ? text : text.substring(0, 12000);
        _page = 0;
        _error = null;
      });
    }
  }

  @override
  void dispose() {
    _channel.setMethodCallHandler(null);
    _input.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted) {
        return;
      }
      if (data?.text == null || data!.text!.trim().isEmpty) {
        setState(
          () => _error =
              'Chưa có nội dung để dán. Bạn có thể nhập đường link trực tiếp.',
        );
        return;
      }
      _receive(data.text!);
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa đọc được bộ nhớ tạm. Bạn có thể nhập trực tiếp hoặc chia sẻ đường link vào Lynveris.',
        );
      }
    }
  }

  Future<void> _check() async {
    FocusScope.of(context).unfocus();
    final urls = extractUrls(_input.text);
    if (urls.isEmpty) {
      setState(
        () => _error = 'Chưa tìm thấy đường link hợp lệ. Hãy nhập đầy đủ http:// hoặc https://.',
      );
      return;
    }
    String? selected = urls.length == 1 ? urls.first : null;
    if (urls.length > 1) {
      selected = await showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        builder: (context) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.sizeOf(context).height * .75,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Chọn đường link cần kiểm tra',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 8),
                  const Text('Chỉ đường link bạn chọn được gửi đến máy chủ.'),
                  const SizedBox(height: 16),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: urls.length,
                      separatorBuilder: (_, _) => const Divider(),
                      itemBuilder: (context, i) => ListTile(
                        contentPadding: EdgeInsets.zero,
                        leading: const Icon(Icons.link),
                        title: Text(
                          Uri.parse(urls[i]).host,
                          textDirection: TextDirection.ltr,
                        ),
                        subtitle: Text(
                          urls[i],
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          textDirection: TextDirection.ltr,
                        ),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => Navigator.pop(context, urls[i]),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    if (selected == null || !mounted) {
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await widget.api.check(selected, store);
      try {
        await store.addResult(result);
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Có kết quả nhưng chưa lưu được lịch sử trên thiết bị.',
              ),
            ),
          );
        }
      }
      if (mounted) {
        // A completed request must release input before navigating to its result.
        setState(() => _busy = false);
        unawaited(
          Navigator.push<void>(
            context,
            MaterialPageRoute<void>(builder: (_) => ResultPage(result: result)),
          ),
        );
      }
    } on ApiFailure catch (e) {
      if (mounted) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _error = 'Chưa hoàn tất kiểm tra. Vui lòng thử lại; hiện chưa có kết luận.',
        );
      }
    } finally {
      if (mounted) {
        setState(() => _busy = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!store.onboardingDone) {
      return Onboarding(
        onStart: () async {
          store.onboardingDone = true;
          await store.persist();
        },
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final content = switch (_page) {
          1 => _history(),
          2 => SettingsPage(store: store, api: widget.api),
          _ => _home(),
        };
        return Scaffold(
          appBar: wide
              ? null
              : AppBar(
                  title: const Brand(),
                  toolbarHeight: 78,
                  actions: [
                    IconButton(
                      tooltip: 'Cài đặt và quyền riêng tư',
                      onPressed: () => setState(() => _page = 2),
                      icon: const Icon(Icons.tune),
                    ),
                  ],
                ),
          body: SafeArea(
            child: Row(
              children: [
                if (wide)
                  Container(
                    width: 244,
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      border: Border(
                        right: BorderSide(color: Color(0xFFE3EAE6)),
                      ),
                    ),
                    padding: const EdgeInsets.fromLTRB(24, 32, 24, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Brand(),
                        const SizedBox(height: 8),
                        const Text(
                          'An tâm cùng gia đình',
                          style: TextStyle(color: muted),
                        ),
                        const SizedBox(height: 52),
                        for (final (i, icon, label) in [
                          (0, Icons.search_rounded, 'Kiểm tra'),
                          (1, Icons.history_rounded, 'Lịch sử'),
                          (2, Icons.tune_rounded, 'Cài đặt'),
                        ])
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              selected: _page == i,
                              selectedTileColor: const Color(0xFFE8F3EC),
                              selectedColor: teal,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                              leading: Icon(icon),
                              title: Text(
                                label,
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              onTap: () => setState(() => _page = i),
                            ),
                          ),
                        const Spacer(),
                        const Icon(Icons.lock_outline, color: teal),
                        const SizedBox(height: 12),
                        const Text(
                          'Bạn luôn nắm quyền',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Không đọc tin nhắn.\nKhông tự mở đường link.',
                          style: TextStyle(color: muted, height: 1.6),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          'LYNVERIS · 0.1.0',
                          style: TextStyle(
                            color: muted,
                            fontSize: 11,
                            letterSpacing: 1.6,
                          ),
                        ),
                      ],
                    ),
                  ),
                Expanded(
                  child: Column(
                    children: [
                      if (store.storageError != null)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: Semantics(
                            liveRegion: true,
                            child: Text(
                              store.storageError!,
                              style: const TextStyle(color: Color(0xFF9D302D)),
                            ),
                          ),
                        ),
                      Expanded(child: content),
                      if (!wide && _page == 0)
                        Container(
                          color: Colors.white,
                          padding: const EdgeInsets.fromLTRB(22, 12, 22, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_error != null)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 12),
                                  child: Semantics(
                                    liveRegion: true,
                                    child: Text(
                                      _error!,
                                      style: const TextStyle(
                                        color: Color(0xFF9D302D),
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ),
                              _checkButton(),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          bottomNavigationBar: wide
              ? null
              : NavigationBar(
                  selectedIndex: _page,
                  onDestinationSelected: (i) => setState(() => _page = i),
                  backgroundColor: Colors.white,
                  destinations: const [
                    NavigationDestination(
                      icon: Icon(Icons.search_rounded),
                      label: 'Kiểm tra',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.history_rounded),
                      label: 'Lịch sử',
                    ),
                    NavigationDestination(
                      icon: Icon(Icons.tune_rounded),
                      label: 'Cài đặt',
                    ),
                  ],
                ),
        );
      },
    );
  }

  Widget _checkButton() => FilledButton.icon(
    onPressed: _busy ? null : _check,
    icon: _busy
        ? const SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2),
          )
        : const Icon(Icons.search_rounded),
    label: Text(_busy ? 'Đang kiểm tra đường link…' : 'Kiểm tra đường link'),
  );

  Widget _home() => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (MediaQuery.sizeOf(context).width >= 500) ...[
          const Eyebrow('MỘT NHỊP DỪNG, THÊM AN TÂM'),
          const SizedBox(height: 14),
        ],
        Text(
          'Đường link này\ncó đáng tin?',
          style: TextStyle(
            fontSize: MediaQuery.sizeOf(context).width < 500 ? 28 : 40,
            height: 1.15,
            fontWeight: FontWeight.w800,
            letterSpacing: -1.4,
          ),
        ),
        const SizedBox(height: 16),
        if (MediaQuery.sizeOf(context).width >= 500) ...[
          const Text(
            'Kiểm tra địa chỉ và dấu hiệu đáng ngờ trước khi bạn mở.',
            style: TextStyle(fontSize: 17, height: 1.6, color: muted),
          ),
          const SizedBox(height: 30),
        ],
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: const Color(0xFFDFE8E2)),
            boxShadow: [
              BoxShadow(
                color: ink.withValues(alpha: .035),
                blurRadius: 30,
                offset: const Offset(0, 12),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Dán đường link hoặc tin nhắn',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xoá nội dung',
                    onPressed: _busy
                        ? null
                        : () {
                            _input.clear();
                            setState(() => _error = null);
                          },
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _input,
                enabled: !_busy,
                minLines: 3,
                maxLines: 7,
                maxLength: 12000,
                style: const TextStyle(fontSize: 17, height: 1.5),
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText:
                      'https://…\n\nHoặc dán tin nhắn có đường link ở đây',
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_error != null) {
                    setState(() => _error = null);
                  }
                },
              ),
              const SizedBox(height: 12),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _busy ? null : _paste,
                  icon: const Icon(Icons.content_paste_rounded, size: 20),
                  label: const Text('Dán từ bộ nhớ tạm'),
                ),
              ),
              const SizedBox(height: 12),
              if (MediaQuery.sizeOf(context).width >= 960) _checkButton(),
              if (_busy)
                const Padding(
                  padding: EdgeInsets.only(top: 12),
                  child: Text(
                    'Đang chờ kết quả từ máy chủ. Không mở đường link.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: muted),
                  ),
                ),
              if (_error != null && MediaQuery.sizeOf(context).width >= 960)
                Padding(
                  padding: const EdgeInsets.only(top: 16),
                  child: Semantics(
                    liveRegion: true,
                    child: Text(
                      _error!,
                      style: const TextStyle(
                        color: Color(0xFF9D302D),
                        fontSize: 16,
                        height: 1.5,
                      ),
                    ),
                  ),
                ),
              const SizedBox(height: 18),
              const Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.lock_outline_rounded, size: 18, color: muted),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Chỉ URL bạn chọn được gửi để kiểm tra. Nội dung còn lại của tin nhắn ở trên thiết bị.',
                      style: TextStyle(color: muted, height: 1.5, fontSize: 13),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 30),
        Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2E7),
            borderRadius: BorderRadius.circular(22),
          ),
          child: const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.favorite_border_rounded, color: teal, size: 28),
              SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Chậm một chút, chắc chắn hơn',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      'Tin nhắn thúc giục chuyển tiền hay cung cấp OTP? Hãy gọi lại qua số đã biết hoặc nhờ người thân kiểm tra.',
                      style: TextStyle(color: muted, height: 1.6, fontSize: 15),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 28),
        const Text(
          'Một vài điều bạn nên biết',
          style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        const InfoRow(
          icon: Icons.language_rounded,
          title: 'Nhìn vào tên miền thật',
          text:
              'Tên thương hiệu có thể xuất hiện ở bất kỳ đâu trong đường link.',
        ),
        const InfoRow(
          icon: Icons.https_outlined,
          title: 'Có HTTPS vẫn cần kiểm tra',
          text:
              'Biểu tượng ổ khoá không xác nhận trang thuộc tổ chức bạn biết.',
        ),
        const InfoRow(
          icon: Icons.forum_outlined,
          title: 'Phân vân thì hỏi người thân',
          text: 'Bạn có thể chủ động chia sẻ kết quả, không kèm nội dung tin nhắn.',
        ),
        const SizedBox(height: 20),
        const Text(
          'Lynveris có thể cảnh báo nhầm hoặc bỏ sót. Kết quả giúp bạn cân nhắc, không bảo đảm an toàn tuyệt đối.',
          style: TextStyle(fontSize: 13, color: muted, height: 1.6),
        ),
      ],
    ),
  );
  Widget _history() => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('NHỮNG LẦN BẠN ĐÃ KIỂM TRA'),
        const SizedBox(height: 14),
        const Text(
          'Lịch sử',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 12),
        const Text(
          'Lưu trên thiết bị tối đa 30 ngày, 100 kết quả. Không lưu đường dẫn, tham số hoặc thông tin đăng nhập.',
          style: TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 24),
        if (store.history.isEmpty) ...[
          const SizedBox(height: 36),
          const Icon(Icons.history_toggle_off_rounded, size: 64, color: teal),
          const SizedBox(height: 20),
          const Text(
            'Bạn quyết định điều gì được lưu',
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 12),
          Text(
            store.saveHistory
                ? 'Chưa có kết quả nào. Lần kiểm tra tiếp theo sẽ xuất hiện ở đây.'
                : 'Lịch sử đang tắt. Bật lưu nếu bạn muốn xem lại kết quả trên thiết bị này.',
            style: const TextStyle(color: muted, height: 1.6),
          ),
          const SizedBox(height: 20),
          if (!store.saveHistory)
            FilledButton(
              onPressed: () => store.setHistory(true),
              child: const Text('Bật lưu lịch sử'),
            ),
        ] else ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline),
              label: const Text('Xoá tất cả'),
              onPressed: () async {
                if (await confirm(
                  context,
                  'Xoá toàn bộ lịch sử trên thiết bị?',
                )) {
                  await store.clearHistory();
                }
              },
            ),
          ),
          for (final item in store.history)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Material(
                color: Colors.white,
                borderRadius: BorderRadius.circular(18),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(16),
                  leading: const Icon(Icons.history_rounded, color: muted),
                  title: Text(
                    item['url']['hostname'],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    'Kết quả đã lưu · ${formatTime(item['checked_at'])}',
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ResultPage(result: item),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Xoá kết quả',
                    icon: const Icon(Icons.delete_outline),
                    onPressed: () => store.deleteItem(item['id']),
                  ),
                ),
              ),
            ),
        ],
      ],
    ),
  );
}

class Onboarding extends StatelessWidget {
  const Onboarding({super.key, required this.onStart});
  final VoidCallback onStart;
  @override
  Widget build(BuildContext context) => Scaffold(
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
        child: FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.arrow_forward_rounded),
          label: const Text('Bắt đầu kiểm tra'),
        ),
      ),
    ),
    body: SafeArea(
      child: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Brand(),
            const SizedBox(height: 52),
            Container(
              width: 104,
              height: 104,
              decoration: BoxDecoration(
                color: const Color(0xFFE2EFE4),
                borderRadius: BorderRadius.circular(32),
              ),
              child: const Icon(Icons.shield_outlined, size: 60, color: teal),
            ),
            const SizedBox(height: 32),
            const Text(
              'Bình tĩnh trước mỗi đường link',
              style: TextStyle(
                fontSize: 38,
                height: 1.2,
                fontWeight: FontWeight.w800,
                letterSpacing: -1,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Một người bạn đồng hành nhỏ, giúp cả gia đình nhận ra dấu hiệu cần thận trọng.',
              style: TextStyle(color: muted, fontSize: 18, height: 1.6),
            ),
            const SizedBox(height: 32),
            const InfoRow(
              icon: Icons.content_paste_rounded,
              title: 'Dán hoặc chia sẻ vào Lynveris',
              text: 'Nếu có nhiều đường link, bạn chọn link cần kiểm tra.',
            ),
            const InfoRow(
              icon: Icons.manage_search_rounded,
              title: 'Đọc lý do, biết cách xử lý',
              text: 'Nhìn rõ hostname thực tế cùng nguồn và giới hạn kiểm tra.',
            ),
            const InfoRow(
              icon: Icons.privacy_tip_outlined,
              title: 'Quyền riêng tư trong tay bạn',
              text: 'Không tự đọc tin nhắn, danh bạ hay bộ nhớ tạm. Lịch sử và tra nguồn bên thứ ba mặc định tắt.',
            ),
            const SizedBox(height: 24),
            const Text(
              'Kết quả có thể bỏ sót hoặc cảnh báo nhầm. Không nhập mật khẩu, OTP hoặc chuyển tiền khi chưa xác minh.',
              style: TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    ),
  );
}

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.result});
  final Map<String, dynamic> result;
  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  Timer? _expiryTimer;
  Map<String, dynamic> get result => widget.result;
  @override
  void initState() {
    super.initState();
    final expiry = DateTime.tryParse(result['threat']?['expires_at'] ?? '');
    if (expiry != null && expiry.isAfter(DateTime.now())) {
      _expiryTimer = Timer(expiry.difference(DateTime.now()), () {
        if (mounted) {
          setState(() {});
        }
      });
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final historical = result['history_redacted'] == true;
    final expiry = DateTime.tryParse(result['threat']?['expires_at'] ?? '');
    final expired =
        result['threat']?['status'] == 'detected' &&
        (expiry == null || !expiry.isAfter(DateTime.now()));
    final archival = historical || expired;
    final verdict = archival ? 'insufficient' : result['verdict'] as String;
    final color = verdictColor(verdict),
        url = result['url'] as Map,
        threat = result['threat'] as Map,
        model = result['model'] as Map;
    final signals = (result['signals'] as List)
        .where((s) => !archival || s['source'] != 'threat')
        .toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(historical ? 'Kết quả đã lưu' : 'Kết quả kiểm tra'),
      ),
      body: PageBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: color.withValues(alpha: .08),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: color.withValues(alpha: .2)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(verdictIcon(verdict), size: 44, color: color),
                  const SizedBox(height: 20),
                  Text(
                    archival
                        ? 'Kết quả tại lần kiểm tra trước'
                        : result['title'],
                    style: TextStyle(
                      fontSize: 30,
                      height: 1.25,
                      fontWeight: FontWeight.w800,
                      color: color,
                    ),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    archival
                        ? 'Đây là bản lưu, không phản ánh trạng thái hiện tại. Hãy dán lại URL gốc để kiểm tra mới.'
                        : result['summary'],
                    style: const TextStyle(fontSize: 17, height: 1.6),
                  ),
                  const SizedBox(height: 20),
                  const Eyebrow('TÊN MIỀN THỰC TẾ'),
                  const SizedBox(height: 8),
                  SelectableText(
                    url['hostname'],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if (url['unicode_hostname'] != url['hostname'])
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: SelectableText(
                        'Unicode: ${url['unicode_hostname']}',
                        textDirection: TextDirection.ltr,
                      ),
                    ),
                  const SizedBox(height: 10),
                  Text(
                    'Miền đăng ký: ${url['registered_domain'] ?? 'Địa chỉ IP'}',
                    style: const TextStyle(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Text(
              'Kiểm tra lúc ${formatTime(result['checked_at'])}',
              style: const TextStyle(color: muted, fontSize: 13),
            ),
            if (historical)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'URL đã được rút về hostname khi lưu để loại thông tin riêng tư.',
                  style: TextStyle(color: muted),
                ),
              ),
            const SizedBox(height: 30),
            const Text(
              'Vì sao có kết quả này?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            if (signals.isEmpty)
              const Text(
                'Chưa ghi nhận dấu hiệu cụ thể từ các kiểm tra đang hoạt động. Đây chưa phải bằng chứng đường link hợp lệ.',
                style: TextStyle(height: 1.6, color: muted),
              ),
            for (final s in signals.where((s) => s['severity'] != 'info'))
              InfoRow(
                icon: s['source'] == 'threat'
                    ? Icons.radar
                    : s['source'] == 'model'
                    ? Icons.analytics_outlined
                    : Icons.link,
                title: s['title'],
                text: '${s['detail']}\nNguồn: ${sourceLabel(s['source'])}',
              ),
            if (signals.isNotEmpty &&
                signals.every((s) => s['severity'] == 'info'))
              const Text(
                'Chỉ có thông tin mô tả URL; chưa có bằng chứng đủ để kết luận.',
                style: TextStyle(color: muted, height: 1.6),
              ),
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 16),
            const Text(
              'Bạn nên làm gì?',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            for (final action in result['actions'] as List)
              Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(
                      Icons.check_circle_outline,
                      color: teal,
                      size: 22,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        action,
                        style: const TextStyle(fontSize: 16, height: 1.6),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                try {
                  await SharePlus.instance.share(
                    ShareParams(
                      title: 'Kết quả Lynveris',
                      text:
                          'Lynveris · ${archival ? 'Kết quả cũ, cần kiểm tra lại' : result['title']}\nHostname: ${url['hostname']}\nThời điểm: ${formatTime(result['checked_at'])}\nHãy xác minh qua ứng dụng chính thức. Không cung cấp mật khẩu hoặc OTP.\nKết quả có thể bỏ sót hoặc cảnh báo nhầm.'
                          '${!archival && threat['status'] == 'detected' ? '\nAdvisory provided by Google\nhttps://developers.google.com/safe-browsing/v4/support' : ''}',
                    ),
                  );
                } catch (_) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Chưa mở được bảng chia sẻ trên thiết bị này.',
                        ),
                      ),
                    );
                  }
                }
              },
              icon: const Icon(Icons.ios_share_rounded),
              label: const Text('Nhờ người thân xem giúp'),
            ),
            const SizedBox(height: 24),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: const Text('Nguồn và giới hạn kiểm tra'),
              children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Google Safe Browsing: ${threatStatus(threat['status'])}',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      if (threat['checked_at'] != null)
                        Text(
                          'Thời điểm tra: ${formatTime(threat['checked_at'])}',
                        ),
                      if (threat['expires_at'] != null)
                        Text(
                          'Hiệu lực đến: ${formatTime(threat['expires_at'])}',
                        ),
                      if (threat['cached'] == true)
                        const Text(
                          'Kết quả từ cache còn hạn tại lúc kiểm tra.',
                        ),
                      if (threat['attribution'] != null) ...[
                        const SizedBox(height: 8),
                        Text(threat['attribution']),
                        Link(
                          uri: Uri.parse(
                            'https://developers.google.com/safe-browsing/v4/support',
                          ),
                          target: LinkTarget.blank,
                          builder: (context, followLink) => TextButton(
                            onPressed: followLink,
                            child: const Text('Thông tin cảnh báo từ Google'),
                          ),
                        ),
                        Link(
                          uri: Uri.parse('https://www.antiphishing.org/'),
                          target: LinkTarget.blank,
                          builder: (context, followLink) => TextButton(
                            onPressed: followLink,
                            child: const Text('Tìm hiểu về lừa đảo phishing'),
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      Text(
                        'Mô hình: ${model['status'] == 'ready' ? model['version'] : 'Chưa sẵn sàng'}',
                      ),
                      if (model['score'] != null)
                        Text(
                          'Điểm phân loại: ${model['score'].toStringAsFixed(3)} · ngưỡng ${model['threshold']}\nKhông phải xác suất lừa đảo.',
                        ),
                      const SizedBox(height: 12),
                      for (final limitation in result['limitations'] as List)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(
                            '• $limitation',
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                        ),
                      for (final s in signals.where(
                        (s) => s['severity'] == 'info',
                      ))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            '${s['title']}: ${s['detail']}',
                            style: const TextStyle(color: muted, height: 1.6),
                          ),
                        ),
                      if (result['versions'] is Map)
                        Text(
                          'Đặc trưng: ${result['versions']['features']} · thương hiệu ${result['versions']['brands']}',
                          style: const TextStyle(fontSize: 12, color: muted),
                        ),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text(
                historical ? 'Địa chỉ đã lược thông tin' : 'URL bạn đã gửi',
              ),
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: SelectableText(
                    url['original'],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(height: 1.5),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Quay lại'),
            ),
          ],
        ),
      ),
    );
  }
}

class SettingsPage extends StatefulWidget {
  const SettingsPage({super.key, required this.store, required this.api});
  final AppStore store;
  final ApiClient api;
  @override
  State<SettingsPage> createState() => _SettingsPageState();
}

class _SettingsPageState extends State<SettingsPage> {
  bool _deleting = false;
  AppStore get store => widget.store;
  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Eyebrow('THEO CÁCH CỦA BẠN'),
        const SizedBox(height: 14),
        const Text(
          'Cài đặt',
          style: TextStyle(fontSize: 36, fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 32),
        const Text(
          'Dễ đọc, dễ sử dụng',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 18),
        Text('Cỡ chữ trong ứng dụng · ${(store.textScale * 100).round()}%'),
        Slider(
          value: store.textScale,
          min: 1,
          max: 1.5,
          divisions: 5,
          label: '${(store.textScale * 100).round()}%',
          onChanged: (value) {
            store.textScale = value;
            store.persist();
          },
        ),
        const Text(
          'Ứng dụng cũng tôn trọng cỡ chữ bạn đã chọn trong hệ điều hành.',
          style: TextStyle(color: muted, height: 1.6),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const SizedBox(height: 20),
        const Text(
          'Quyền riêng tư',
          style: TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Lưu lịch sử trên thiết bị'),
          subtitle: const Text(
            'Tối đa 30 ngày, 100 mục. Tắt lựa chọn này sẽ xoá bản lưu hiện có.',
          ),
          value: store.saveHistory,
          onChanged: (value) async {
            if (value ||
                await confirm(context, 'Tắt lưu và xoá lịch sử hiện có?')) {
              await store.setHistory(value);
            }
          },
        ),
        const Divider(),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Tra Google Safe Browsing'),
          subtitle: const Text(
            'Gửi URL được chọn, gồm đường dẫn và tham số, từ backend đến Google. URL có thể chứa dữ liệu riêng tư. Google vẫn có thể bỏ sót hoặc cảnh báo nhầm.',
          ),
          value: store.useThreat,
          onChanged: (value) async {
            store.useThreat = value;
            await store.persist();
          },
        ),
        const Divider(),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: const Text('Đóng góp thống kê tối thiểu'),
          subtitle: const Text(
            'Tự nguyện. Chỉ lưu mức cảnh báo, trạng thái nguồn, phiên bản mô hình và giờ kiểm tra trong 7 ngày. Không lưu URL, tin nhắn hay IP trong dữ liệu nghiên cứu.',
          ),
          value: store.researchConsent,
          onChanged: (value) async {
            store.researchConsent = value;
            await store.persist();
          },
        ),
        const SizedBox(height: 16),
        OutlinedButton.icon(
          onPressed: _deleting
              ? null
              : () async {
                  setState(() => _deleting = true);
                  try {
                    await widget.api.deleteResearch(store);
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Đã xoá thống kê gắn với thiết bị này trên máy chủ.',
                          ),
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            e is ApiFailure
                                ? e.message
                                : 'Chưa xoá được thống kê. Hãy thử lại.',
                          ),
                        ),
                      );
                    }
                  } finally {
                    if (mounted) {
                      setState(() => _deleting = false);
                    }
                  }
                },
          icon: const Icon(Icons.delete_outline),
          label: Text(_deleting ? 'Đang xoá…' : 'Xoá thống kê trên máy chủ'),
        ),
        const SizedBox(height: 28),
        const Divider(),
        const InfoRow(
          icon: Icons.lock_outline,
          title: 'Chỉ kiểm tra khi bạn yêu cầu',
          text: 'Không tự đọc tin nhắn, danh bạ hoặc clipboard. Không tự truy cập URL. Không gửi thông báo hay kết quả cho người thân khi chưa có thao tác chia sẻ của bạn.',
        ),
        const SizedBox(height: 24),
        ExpansionTile(
          tilePadding: EdgeInsets.zero,
          title: const Text('Kết nối máy chủ'),
          subtitle: Text(
            store.apiBase,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          children: [
            const Text(
              'Dùng HTTPS cho máy chủ thật. Android Emulator dùng http://10.0.2.2:8000; bản xem thử trên máy dùng http://127.0.0.1:8000.',
              style: TextStyle(color: muted, height: 1.6),
            ),
            const SizedBox(height: 12),
            OutlinedButton(
              onPressed: () async {
                final controller = TextEditingController(text: store.apiBase);
                final value = await showDialog<String>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Địa chỉ API'),
                    content: TextField(
                      controller: controller,
                      keyboardType: TextInputType.url,
                      decoration: const InputDecoration(labelText: 'https://…'),
                      autocorrect: false,
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Huỷ'),
                      ),
                      FilledButton(
                        onPressed: () =>
                            Navigator.pop(context, controller.text.trim()),
                        child: const Text('Lưu'),
                      ),
                    ],
                  ),
                );
                if (value != null) {
                  try {
                    widget.api.endpoint(value, '/health');
                    store.apiBase = value;
                    await store.persist();
                  } on ApiFailure catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context)
                          .showSnackBar(SnackBar(content: Text(e.message)));
                    }
                  }
                }
                Future<void>.delayed(
                  const Duration(seconds: 1),
                  controller.dispose,
                );
              },
              child: const Text('Đổi địa chỉ API'),
            ),
            const SizedBox(height: 16),
          ],
        ),
        const SizedBox(height: 28),
        const Text(
          'Lynveris 0.1.0',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Công cụ hỗ trợ nhận diện đường link lừa đảo cho gia đình. Chưa có kết quả kiểm chứng recall và tỉ lệ báo nhầm trên dữ liệu độc lập.',
          style: TextStyle(color: muted, height: 1.6),
        ),
      ],
    ),
  );
}

class PageBody extends StatelessWidget {
  const PageBody({super.key, required this.child});
  final Widget child;
  @override
  Widget build(BuildContext context) => SingleChildScrollView(
    padding: EdgeInsets.symmetric(
      horizontal: MediaQuery.sizeOf(context).width < 500 ? 22 : 48,
      vertical: MediaQuery.sizeOf(context).width < 500 ? 24 : 32,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: child,
      ),
    ),
  );
}

class Eyebrow extends StatelessWidget {
  const Eyebrow(this.text, {super.key});
  final String text;
  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      fontSize: 11,
      letterSpacing: 1.8,
      fontWeight: FontWeight.w700,
      color: teal,
    ),
  );
}

class InfoRow extends StatelessWidget {
  const InfoRow({
    super.key,
    required this.icon,
    required this.title,
    required this.text,
  });
  final IconData icon;
  final String title, text;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 14),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: const Color(0xFFE9F0EC),
            borderRadius: BorderRadius.circular(13),
          ),
          child: Icon(icon, color: teal, size: 23),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                text,
                style: const TextStyle(fontSize: 15, color: muted, height: 1.6),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

Future<bool> confirm(BuildContext context, String title) async =>
    await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(title),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Giữ lại'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Xoá'),
          ),
        ],
      ),
    ) ??
    false;
String formatTime(String? value) {
  final d = DateTime.tryParse(value ?? '')?.toLocal();
  if (d == null) {
    return 'Không có thời điểm';
  }
  String p(int n) => n.toString().padLeft(2, '0');
  return '${p(d.hour)}:${p(d.minute)} · ${p(d.day)}/${p(d.month)}/${d.year}';
}

Color verdictColor(String v) => switch (v) {
  'high' => const Color(0xFFA83331),
  'caution' => const Color(0xFF885B12),
  'no_signs' => teal,
  _ => const Color(0xFF486373),
};
IconData verdictIcon(String v) => switch (v) {
  'high' => Icons.gpp_bad_outlined,
  'caution' => Icons.warning_amber_rounded,
  'no_signs' => Icons.verified_user_outlined,
  _ => Icons.help_outline_rounded,
};
String sourceLabel(String v) => switch (v) {
  'model' => 'mô hình đặc trưng URL',
  'threat' => 'tin đe doạ',
  _ => 'phân tích URL',
};
String threatStatus(String? v) => switch (v) {
  'detected' => 'Có ghi nhận tại thời điểm tra',
  'not_found' => 'Chưa ghi nhận, không đồng nghĩa an toàn',
  'error' => 'Lỗi tra cứu',
  'timeout' => 'Quá thời gian chờ',
  'quota' => 'Hết quota hoặc giới hạn lượt',
  'not_configured' => 'Máy chủ chưa cấu hình khoá',
  _ => 'Chưa bật tra nguồn',
};
