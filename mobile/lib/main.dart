import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';

import 'api.dart';
import 'build_config.dart';
import 'store.dart';
import 'url_input.dart';
import 'visuals.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final store = AppStore(DeviceStorage());
  await store.load();
  runApp(LynverisApp(store: store));
}

class LynverisApp extends StatefulWidget {
  const LynverisApp({super.key, required this.store, this.api});
  final AppStore store;
  final ApiClient? api;

  @override
  State<LynverisApp> createState() => _LynverisAppState();
}

class _LynverisAppState extends State<LynverisApp> {
  final _defaultApi = ApiClient();
  AppStore get store => widget.store;

  @override
  void dispose() {
    _defaultApi.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: store,
    builder: (context, _) => MaterialApp(
      title: 'Lynveris',
      debugShowCheckedModeBanner: false,
      locale: const Locale('vi'),
      supportedLocales: const [Locale('vi')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      theme: lynverisTheme(),
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: MediaQuery.textScalerOf(context)
              .clamp(minScaleFactor: store.textScale),
        ),
        child: child!,
      ),
      home: AppShell(store: store, api: widget.api ?? _defaultApi),
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
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF234678), night],
          ),
          border: Border.all(color: aqua.withValues(alpha: .35)),
          borderRadius: BorderRadius.circular(14),
        ),
        child: const Icon(Icons.shield_outlined, color: aqua, size: 25),
      ),
      const SizedBox(width: 11),
      Flexible(
        child: Text(
          'Lynveris',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ink,
            fontSize: 24,
            fontWeight: FontWeight.w900,
            letterSpacing: -.9,
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
  String _scanHost = '';
  int _requestGeneration = 0;
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
      _requestGeneration++;
      setState(() {
        _busy = false;
        _input.text = text.length <= 12000 ? text : text.substring(0, 12000);
        _page = 0;
        _error = null;
      });
      // A new Android share must reveal its input even while a result/dialog is open.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((route) => route.isFirst);
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
    if (_busy) return;
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
    final urlToCheck = selected;
    if (urlToCheck == null || !mounted) {
      return;
    }
    final generation = ++_requestGeneration;
    final dwell = MediaQuery.disableAnimationsOf(context)
        ? Duration.zero
        : const Duration(milliseconds: 720);
    final elapsed = Stopwatch()..start();
    setState(() {
      _busy = true;
      _scanHost = Uri.tryParse(urlToCheck)?.host ?? '';
      _error = null;
    });
    try {
      final result = await widget.api.check(urlToCheck, store);
      if (!mounted || generation != _requestGeneration) return;
      final remaining = dwell - elapsed.elapsed;
      if (remaining > Duration.zero) await Future<void>.delayed(remaining);
      if (!mounted || generation != _requestGeneration) return;
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
      if (mounted && generation == _requestGeneration) {
        // A completed request must release input before navigating to its result.
        setState(() => _busy = false);
        unawaited(
          Navigator.push<void>(
            context,
            _resultRoute(result, dwell == Duration.zero),
          ),
        );
      }
    } on ApiFailure catch (e) {
      if (mounted && generation == _requestGeneration) {
        setState(() => _error = e.message);
      }
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(
          () => _error = 'Chưa hoàn tất kiểm tra. Vui lòng thử lại; hiện chưa có kết luận.',
        );
      }
    } finally {
      if (mounted && generation == _requestGeneration) {
        setState(() => _busy = false);
      }
    }
  }

  void _returnToInput() {
    _requestGeneration++;
    setState(() => _busy = false);
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
    if (_busy) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _returnToInput();
        },
        child: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Scaffold(
            backgroundColor: night,
            body: SafeArea(
              child: ScanPanel(host: _scanHost, onBack: _returnToInput),
            ),
          ),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 960;
        final typing = MediaQuery.viewInsetsOf(context).bottom > 0;
        final page = switch (_page) {
          1 => _history(),
          2 => SettingsPage(store: store, api: widget.api),
          _ => _home(wide),
        };
        return Scaffold(
          appBar: AppBar(
            title: const Brand(),
            toolbarHeight: 65,
            actions: [
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: IconButton(
                  tooltip: 'Cài đặt và quyền riêng tư',
                  onPressed: () => _selectPage(2),
                  icon: const Icon(Icons.tune_rounded),
                ),
              ),
            ],
          ),
          body: SafeArea(
            bottom: false,
            child: Row(
              children: [
                if (wide)
                  NavigationRail(
                    extended: true,
                    minExtendedWidth: 188,
                    backgroundColor: Colors.white,
                    selectedIndex: _page,
                    onDestinationSelected: _selectPage,
                    destinations: [
                      for (final destination in _destinations)
                        NavigationRailDestination(
                          icon: destination.icon,
                          label: Text(destination.label),
                        ),
                    ],
                  ),
                Expanded(
                  child: Column(
                    children: [
                      if (store.storageError case final message?)
                        Padding(
                          padding: const EdgeInsets.all(14),
                          child: _Notice(message),
                        ),
                      Expanded(child: page),
                      if (!wide && _page == 0)
                        Container(
                          width: double.infinity,
                          decoration: const BoxDecoration(
                            color: Colors.white,
                            border: Border(top: BorderSide(color: edge)),
                          ),
                          padding: const EdgeInsets.fromLTRB(18, 10, 18, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_error case final message?)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _Notice(message),
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
          bottomNavigationBar: wide || typing
              ? null
              : NavigationBar(
                  selectedIndex: _page,
                  onDestinationSelected: _selectPage,
                  destinations: _destinations,
                ),
        );
      },
    );
  }

  static const _destinations = [
    NavigationDestination(icon: Icon(Icons.radar_rounded), label: 'Kiểm tra'),
    NavigationDestination(icon: Icon(Icons.history_rounded), label: 'Lịch sử'),
    NavigationDestination(icon: Icon(Icons.tune_rounded), label: 'Cài đặt'),
  ];

  void _selectPage(int index) {
    FocusScope.of(context).unfocus();
    setState(() => _page = index);
  }

  Widget _checkButton() => FilledButton.icon(
    onPressed: store.apiBase.isEmpty ? () => _selectPage(2) : _check,
    icon: const Icon(Icons.radar_rounded, color: aqua),
    label: Text(
      store.apiBase.isEmpty ? 'Thiết lập kết nối' : 'Kiểm tra đường link',
    ),
  );

  Widget _home(bool wide) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const MissionHeader(
          label: 'TRẠM KIỂM TRA ĐƯỜNG LINK',
          title: 'Đường link này\ncó đáng tin?',
          description: 'Nhìn rõ địa chỉ trước khi mở.',
        ),
        if (store.apiBase.isEmpty)
          const InfoRow(
            icon: Icons.cloud_off_outlined,
            title: 'Chưa có địa chỉ máy chủ',
            text: 'Thêm địa chỉ HTTPS của máy chủ Lynveris trong Cài đặt để bắt đầu kiểm tra.',
          ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 11),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Glyph(Icons.link_rounded, size: 34),
                  const SizedBox(width: 9),
                  const Expanded(
                    child: Text(
                      'Đường link hoặc tin nhắn',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: 'Xoá nội dung',
                    onPressed: () {
                      _input.clear();
                      setState(() => _error = null);
                    },
                    icon: const Icon(Icons.close_rounded, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              TextField(
                controller: _input,
                enabled: !_busy,
                minLines: 2,
                maxLines: 6,
                maxLength: 12000,
                style: const TextStyle(fontSize: 16, height: 1.45),
                keyboardType: TextInputType.multiline,
                autocorrect: false,
                enableSuggestions: false,
                decoration: const InputDecoration(
                  hintText: 'https://… hoặc dán tin nhắn ở đây',
                  counterText: '',
                ),
                onChanged: (_) {
                  if (_error != null) setState(() => _error = null);
                },
              ),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  onPressed: _paste,
                  style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                  icon: const Icon(Icons.content_paste_rounded, size: 18),
                  label: const Text('Dán từ bộ nhớ tạm'),
                ),
              ),
              if (wide) _checkButton(),
              if (wide && _error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: _Notice(_error!),
                ),
            ],
          ),
        ),
        const SizedBox(height: 13),
        const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.lock_outline_rounded, size: 17, color: teal),
            SizedBox(width: 8),
            Expanded(
              child: Text(
                'Chỉ đường link bạn chọn được gửi để kiểm tra. Phần còn lại của tin nhắn ở trên thiết bị.',
                style: TextStyle(color: muted, height: 1.45, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 17),
        const SurfaceCard(
          padding: EdgeInsets.symmetric(horizontal: 14, vertical: 3),
          child: ExpansionTile(
            leading: Icon(Icons.lightbulb_outline_rounded, color: teal),
            tilePadding: EdgeInsets.zero,
            title: Text(
              'Ba thói quen giúp kiểm tra link',
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
            ),
            children: [
              InfoRow(
                icon: Icons.language_rounded,
                title: 'Nhìn tên miền thực tế',
                text: 'Tên thương hiệu trong đường dẫn có thể khác tên miền nhận kết nối.',
              ),
              InfoRow(
                icon: Icons.https_outlined,
                title: 'Có HTTPS vẫn cần xác minh',
                text: 'Biểu tượng ổ khoá không xác nhận trang thuộc tổ chức bạn biết.',
              ),
              InfoRow(
                icon: Icons.forum_outlined,
                title: 'Hỏi người thân khi phân vân',
                text: 'Nếu bị thúc giục chuyển tiền hay cung cấp OTP, hãy liên hệ qua số đã biết.',
              ),
              SizedBox(height: 8),
            ],
          ),
        ),
      ],
    ),
  );

  Widget _history() => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        MissionHeader(
          label: 'TRÊN THIẾT BỊ NÀY',
          title: 'Lịch sử kiểm tra',
          description: store.saveHistory
              ? 'Đã lưu ${store.history.length} kết quả. Tối đa 30 ngày hoặc 100 mục.'
              : 'Bạn có thể bật lưu để xem lại những lần kiểm tra.',
          icon: Icons.history_rounded,
        ),
        const SizedBox(height: 14),
        if (store.history.isEmpty)
          SurfaceCard(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                const Glyph(Icons.history_toggle_off_rounded, size: 68),
                const SizedBox(height: 17),
                const Text(
                  'Bạn quyết định điều gì được lưu',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 21,
                    height: 1.2,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  store.saveHistory
                      ? 'Lần kiểm tra tiếp theo sẽ xuất hiện tại đây.'
                      : 'Lịch sử đang tắt. Bản lưu chỉ giữ tên miền của đường link.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: muted, height: 1.5),
                ),
                if (!store.saveHistory) ...[
                  const SizedBox(height: 17),
                  FilledButton(
                    onPressed: () => store.setHistory(true),
                    child: const Text('Bật lưu lịch sử'),
                  ),
                ],
              ],
            ),
          )
        else ...[
          Align(
            alignment: Alignment.centerRight,
            child: TextButton.icon(
              icon: const Icon(Icons.delete_outline_rounded),
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
              padding: const EdgeInsets.only(bottom: 10),
              child: SurfaceCard(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                child: ListTile(
                  leading: Glyph(
                    verdictIcon(item['verdict']),
                    color: verdictColor(item['verdict']),
                  ),
                  title: Text(
                    item['url']['hostname'],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                  subtitle: Text(
                    'Kết quả đã lưu\n${formatTime(item['checked_at'])}',
                    style: const TextStyle(color: muted, height: 1.45),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => ResultPage(result: item),
                    ),
                  ),
                  trailing: IconButton(
                    tooltip: 'Xoá kết quả',
                    icon: const Icon(Icons.delete_outline_rounded),
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

class _Notice extends StatelessWidget {
  const _Notice(this.message);
  final String message;

  @override
  Widget build(BuildContext context) => Semantics(
    liveRegion: true,
    child: DecoratedBox(
      decoration: BoxDecoration(
        color: const Color(0xFFFFEEF0),
        borderRadius: BorderRadius.circular(13),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            const Icon(
              Icons.info_outline_rounded,
              color: Color(0xFF9B3047),
              size: 18,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Color(0xFF86223A), height: 1.4),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

class Onboarding extends StatelessWidget {
  const Onboarding({super.key, required this.onStart});
  final VoidCallback onStart;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Brand(), toolbarHeight: 65),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 8, 18, 16),
        child: FilledButton.icon(
          onPressed: onStart,
          icon: const Icon(Icons.arrow_forward_rounded, color: aqua),
          label: const Text('Bắt đầu kiểm tra'),
        ),
      ),
    ),
    body: const PageBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _WelcomeHero(),
          SizedBox(height: 16),
          SurfaceCard(
            child: Column(
              children: [
                InfoRow(
                  icon: Icons.content_paste_rounded,
                  title: 'Dán hoặc chia sẻ vào Lynveris',
                  text: 'Nếu có nhiều đường link, bạn chọn link cần kiểm tra.',
                ),
                InfoRow(
                  icon: Icons.manage_search_rounded,
                  title: 'Đọc lý do, biết cách xử lý',
                  text: 'Nhìn rõ tên miền thực tế cùng nguồn và giới hạn kiểm tra.',
                ),
                InfoRow(
                  icon: Icons.privacy_tip_outlined,
                  title: 'Quyền riêng tư trong tay bạn',
                  text: 'Lịch sử và tra nguồn bên thứ ba mặc định tắt.',
                ),
              ],
            ),
          ),
          SizedBox(height: 18),
          Text(
            'Kết quả có thể bỏ sót hoặc cảnh báo nhầm. Hãy xác minh trước khi nhập mật khẩu, OTP hoặc chuyển tiền.',
            style: TextStyle(color: muted, height: 1.5),
          ),
        ],
      ),
    ),
  );
}

class _WelcomeHero extends StatelessWidget {
  const _WelcomeHero();

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(30),
      gradient: const RadialGradient(
        center: Alignment(0, -.3),
        radius: .95,
        colors: [Color(0xFF244571), night],
      ),
    ),
    padding: const EdgeInsets.fromLTRB(22, 19, 22, 24),
    child: const Column(
      children: [
        SignalLabel('LYNVERIS  /  KIỂM TRA URL'),
        RadarArt(size: 182),
        Text(
          'Bình tĩnh trước mỗi đường link',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white,
            fontSize: 29,
            fontWeight: FontWeight.w800,
            height: 1.15,
            letterSpacing: -.5,
          ),
        ),
        SizedBox(height: 12),
        Text(
          'Xem địa chỉ thật và những dấu hiệu cần lưu ý trước khi mở.',
          textAlign: TextAlign.center,
          style: TextStyle(color: moon, fontSize: 15, height: 1.5),
        ),
      ],
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
            MissionHeader(
              label: archival ? 'KẾT QUẢ ĐÃ LƯU' : 'KẾT QUẢ PHÂN TÍCH',
              title: archival
                  ? 'Kết quả tại lần kiểm tra trước'
                  : result['title'],
              description: archival
                  ? 'Kết quả được lưu từ lần trước. Dán lại URL gốc để kiểm tra hiện tại.'
                  : result['summary'],
              icon: verdictIcon(verdict),
              accent: switch (verdict) {
                'high' => const Color(0xFFFFA8B3),
                'caution' => const Color(0xFFFFCF89),
                'no_signs' => aqua,
                _ => const Color(0xFFC2CAFF),
              },
            ),
            const SizedBox(height: 12),
            SurfaceCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Glyph(Icons.language_rounded, color: color, size: 35),
                      const SizedBox(width: 10),
                      const Expanded(child: Eyebrow('TÊN MIỀN THỰC TẾ')),
                    ],
                  ),
                  const SizedBox(height: 10),
                  SelectableText(
                    url['hostname'],
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(
                      fontSize: 23,
                      fontWeight: FontWeight.w800,
                      height: 1.2,
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
                  const SizedBox(height: 8),
                  Text(
                    'Miền đăng ký: ${url['registered_domain'] ?? 'Địa chỉ IP'}',
                    style: const TextStyle(color: muted, height: 1.4),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    'Kiểm tra lúc ${formatTime(result['checked_at'])}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ],
              ),
            ),
            if (historical)
              const Padding(
                padding: EdgeInsets.only(top: 12),
                child: Text(
                  'URL đã được rút về hostname khi lưu để loại thông tin riêng tư.',
                  style: TextStyle(color: muted),
                ),
              ),
            const SizedBox(height: 18),
            const _SectionTitle(
              Icons.analytics_outlined,
              'Vì sao có kết quả này?',
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
            const SizedBox(height: 18),
            const _SectionTitle(
              Icons.tips_and_updates_outlined,
              'Bạn nên làm gì?',
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
                          '${!archival && threat['status'] == 'detected' ? '\nNguồn: ${threat['source']}\n${threat['attribution'] ?? ''}\n${threat['advisory_url'] ?? ''}' : ''}',
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
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: ExpansionTile(
                tilePadding: EdgeInsets.zero,
                title: const Text('Nguồn và giới hạn kiểm tra'),
                children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${threat['source']}: ${threatStatus(threat['status'])}',
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        if (threat['partial'] == true)
                          const Text('Tra cứu chưa đầy đủ ở một phần nguồn.'),
                        for (final check in (threat['checks'] as List? ?? []))
                          Padding(
                            padding: const EdgeInsets.only(top: 8, bottom: 8),
                            child: Text(
                              '${check['source']}: ${threatStatus(check['status'])}'
                              '${check['checked_at'] != null ? '\nTra lúc: ${formatTime(check['checked_at'])}' : ''}'
                              '${check['cached'] == true ? '\nCache còn hạn tại lúc kiểm tra.' : ''}',
                            ),
                          ),
                        if (threat['checked_at'] != null)
                          Text(
                            'Thời điểm tra: ${formatTime(threat['checked_at'])}',
                          ),
                        if (threat['expires_at'] != null)
                          Text(
                            'Hiệu lực đến: ${formatTime(threat['expires_at'])}',
                          ),
                        if (threat['feed_received_at'] != null)
                          Text(
                            'Tải feed lúc: ${formatTime(threat['feed_received_at'])}. Đây không phải thời điểm URL được gán nhãn.',
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
                              threat['source'] == 'OpenPhish Community'
                                  ? 'https://openphish.com/phishing_feeds.html'
                                  : 'https://developers.google.com/safe-browsing/v4/support',
                            ),
                            target: LinkTarget.blank,
                            builder: (context, followLink) => TextButton(
                              onPressed: followLink,
                              child: const Text('Thông tin về nguồn cảnh báo'),
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
                        if (model['release_stage'] == 'research')
                          const Text(
                            'Mô hình thử nghiệm · vẫn có thể bỏ sót hoặc cảnh báo nhầm.',
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
            ),
            const SizedBox(height: 10),
            SurfaceCard(
              padding: const EdgeInsets.symmetric(horizontal: 15),
              child: ExpansionTile(
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
            ),
            const SizedBox(height: 10),
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
  bool _connecting = false;
  String? _connectionMessage;
  AppStore get store => widget.store;

  Future<void> _verifyConnection(String address, {required bool save}) async {
    setState(() {
      _connecting = true;
      _connectionMessage = null;
    });
    try {
      await widget.api.verifyServer(address);
      if (!mounted) return;
      if (save) await store.setServer(address);
      if (mounted) {
        setState(() => _connectionMessage = 'Đã kết nối với máy chủ Lynveris.');
      }
    } on ApiFailure catch (error) {
      if (mounted) setState(() => _connectionMessage = error.message);
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  Future<void> _editServer() async {
    var address = store.apiBase;
    final value = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Địa chỉ máy chủ'),
        content: TextFormField(
          initialValue: address,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(hintText: 'https://…'),
          autocorrect: false,
          onChanged: (value) => address = value,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Huỷ'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, address.trim()),
            child: const Text('Kiểm tra và lưu'),
          ),
        ],
      ),
    );
    if (value != null && mounted) await _verifyConnection(value, save: true);
  }

  @override
  Widget build(BuildContext context) => PageBody(
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const MissionHeader(
          label: 'THEO CÁCH CỦA BẠN',
          title: 'Cài đặt',
          description: 'Chỉnh cách hiển thị và dữ liệu bạn muốn chia sẻ.',
          icon: Icons.tune_rounded,
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(
                Icons.text_fields_rounded,
                'Dễ đọc, dễ sử dụng',
              ),
              const SizedBox(height: 18),
              Text(
                'Cỡ chữ trong ứng dụng · ${(store.textScale * 100).round()}%',
              ),
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
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _SectionTitle(Icons.privacy_tip_outlined, 'Quyền riêng tư'),
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
                      await confirm(
                        context,
                        'Tắt lưu và xoá lịch sử hiện có?',
                      )) {
                    await store.setHistory(value);
                  }
                },
              ),
              const Divider(),
              SwitchListTile.adaptive(
                contentPadding: EdgeInsets.zero,
                title: const Text('Tra nguồn tin đe doạ'),
                subtitle: const Text(
                  'Cho phép tra nguồn đang cấu hình trên máy chủ. Với Google, URL gồm đường dẫn và tham số được gửi đến Google. Với OpenPhish, URL được đối chiếu trên backend và không gửi đến nguồn. Nguồn có thể bỏ sót hoặc cảnh báo nhầm.',
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
                label: Text(
                  _deleting ? 'Đang xoá…' : 'Xoá thống kê trên máy chủ',
                ),
              ),
              const SizedBox(height: 8),
              const InfoRow(
                icon: Icons.lock_outline,
                title: 'Chỉ kiểm tra khi bạn yêu cầu',
                text: 'Không tự đọc tin nhắn, danh bạ hoặc clipboard. Lynveris chỉ chia sẻ khi bạn chủ động thao tác.',
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        SurfaceCard(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: ExpansionTile(
            initiallyExpanded: store.apiBase.isEmpty,
            tilePadding: EdgeInsets.zero,
            title: const Text('Kết nối máy chủ'),
            leading: const Glyph(Icons.cloud_outlined),
            subtitle: Text(
              store.apiBase.isEmpty ? 'Chưa thiết lập' : store.apiBase,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            children: [
              if (allowDevelopmentHttp)
                const Text(
                  'Máy chủ cục bộ trên Android Emulator dùng http://10.0.2.2:8000.',
                  style: TextStyle(color: muted, height: 1.6),
                ),
              if (_connecting) const LinearProgressIndicator(),
              if (_connectionMessage case final message?)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  child: Semantics(liveRegion: true, child: Text(message)),
                ),
              if (store.apiBase.isNotEmpty)
                OutlinedButton(
                  onPressed: _connecting
                      ? null
                      : () => _verifyConnection(store.apiBase, save: false),
                  child: const Text('Kiểm tra kết nối'),
                ),
              if (!fixedServer)
                TextButton(
                  onPressed: _connecting ? null : _editServer,
                  child: Text(
                    store.apiBase.isEmpty
                        ? 'Thêm địa chỉ máy chủ'
                        : 'Đổi địa chỉ máy chủ',
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        ),
        const SizedBox(height: 20),
        const Text(
          'Lynveris $appVersion',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        const Text(
          'Công cụ hỗ trợ nhận diện đường link lừa đảo cho gia đình. Xem nguồn, phiên bản mô hình và giới hạn trong từng kết quả kiểm tra.',
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
      horizontal: MediaQuery.sizeOf(context).width < 500 ? 18 : 42,
      vertical: MediaQuery.sizeOf(context).width < 500 ? 14 : 28,
    ),
    child: Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 700),
        child: child,
      ),
    ),
  );
}

Route<void> _resultRoute(Map<String, dynamic> result, bool reduceMotion) =>
    PageRouteBuilder<void>(
      transitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 300),
      reverseTransitionDuration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 220),
      pageBuilder: (context, animation, secondaryAnimation) =>
          ResultPage(result: result),
      transitionsBuilder: (context, animation, secondaryAnimation, child) =>
          FadeTransition(
            opacity: animation.drive(CurveTween(curve: Curves.easeOutCubic)),
            child: SlideTransition(
              position: animation.drive(
                Tween(begin: const Offset(0, .025), end: Offset.zero),
              ),
              child: child,
            ),
          ),
    );

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.icon, this.title);
  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Glyph(icon, size: 36),
      const SizedBox(width: 10),
      Expanded(
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 18,
            height: 1.25,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    ],
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
        Glyph(icon),
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
