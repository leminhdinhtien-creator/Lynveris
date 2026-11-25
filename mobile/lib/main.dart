import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'api.dart';
import 'build_config.dart';
import 'result_page.dart';
import 'store.dart';
import 'url_input.dart';
import 'visuals.dart';

export 'result_page.dart' show ResultPage, verdictLabel;

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
  final _errorKey = GlobalKey();
  final _channel = const MethodChannel('vn.lynveris/share');
  bool _busy = false;
  String _scanHost = '';
  int _requestGeneration = 0;
  String? _error;
  String? _retryUrl;
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
        _retryUrl = null;
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
    final generation = _requestGeneration;
    try {
      final data = await Clipboard.getData(Clipboard.kTextPlain);
      if (!mounted || generation != _requestGeneration) return;
      if (data?.text == null || data!.text!.trim().isEmpty) {
        _showError(
          'Chưa có nội dung để dán. Bạn có thể nhập đường link trực tiếp.',
        );
        return;
      }
      _receive(data.text!);
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        _showError(
          'Chưa đọc được bộ nhớ tạm. Hãy nhập link hoặc chia sẻ vào Lynveris.',
        );
      }
    }
  }

  void _showError(String message, {String? retryUrl}) {
    setState(() {
      _error = message;
      _retryUrl = retryUrl;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final target = _errorKey.currentContext;
      if (!mounted || _error != message || target == null) return;
      unawaited(
        Scrollable.ensureVisible(
          target,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          duration: MediaQuery.disableAnimationsOf(target)
              ? Duration.zero
              : const Duration(milliseconds: 180),
        ),
      );
    });
  }

  Future<void> _check({String? retryUrl}) async {
    if (_busy) return;
    final startGeneration = _requestGeneration;
    FocusScope.of(context).unfocus();
    final urls = retryUrl == null ? extractUrls(_input.text) : [retryUrl];
    if (urls.isEmpty) {
      _showError(
        _input.text.trim().isEmpty
            ? 'Hãy nhập hoặc dán đường link cần kiểm tra.'
            : 'Chưa tìm thấy đường link hợp lệ. Hãy nhập đầy đủ http:// hoặc https://.',
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
    if (urlToCheck == null ||
        !mounted ||
        startGeneration != _requestGeneration) {
      return;
    }
    if (urlToCheck.runes.length > 4096) {
      _showError('Đường link vượt quá 4.096 ký tự.');
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
      _retryUrl = null;
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
            _resultRoute(result, dwell == Duration.zero, () {
              Navigator.of(context).pop();
              if (generation == _requestGeneration) {
                unawaited(_check(retryUrl: urlToCheck));
              }
            }),
          ),
        );
      }
    } on ApiFailure catch (e) {
      if (mounted && generation == _requestGeneration) {
        _showError(e.message, retryUrl: e.retryable ? urlToCheck : null);
      }
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        _showError(
          'Chưa hoàn tất kiểm tra. Vui lòng thử lại; hiện chưa có kết luận.',
          retryUrl: urlToCheck,
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
                          child: _checkButton(),
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
    onPressed: store.apiBase.isEmpty
        ? () => _selectPage(2)
        : () => _check(retryUrl: _retryUrl),
    icon: Icon(
      _retryUrl != null ? Icons.refresh_rounded : Icons.radar_rounded,
      color: aqua,
    ),
    label: Text(
      store.apiBase.isEmpty
          ? 'Thiết lập kết nối'
          : _retryUrl != null
          ? 'Thử lại'
          : 'Kiểm tra đường link',
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
                      setState(() {
                        _error = null;
                        _retryUrl = null;
                      });
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
                  if (_error != null) {
                    setState(() {
                      _error = null;
                      _retryUrl = null;
                    });
                  }
                },
              ),
              if (_error case final message?)
                Padding(
                  key: _errorKey,
                  padding: const EdgeInsets.only(top: 8),
                  child: _Notice(message),
                ),
              ValueListenableBuilder<TextEditingValue>(
                valueListenable: _input,
                builder: (context, value, _) {
                  final urls = extractUrls(value.text);
                  if (urls.isEmpty) return const SizedBox.shrink();
                  final description = urls.length == 1
                      ? 'Đã tìm thấy link tới ${Uri.parse(urls.single).host}'
                      : 'Có ${urls.length} link. Bạn sẽ chọn một link để kiểm tra.';
                  return Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text(
                      description,
                      style: const TextStyle(
                        color: muted,
                        fontSize: 13,
                        height: 1.4,
                      ),
                    ),
                  );
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
                    '${verdictLabel(item['verdict'])}\n${formatTime(item['checked_at'])} · Bản lưu',
                    style: const TextStyle(color: muted, height: 1.45),
                  ),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (resultContext) => ResultPage(
                        result: item,
                        onRecheck: () {
                          Navigator.pop(resultContext);
                          _input.clear();
                          setState(() {
                            _page = 0;
                            _retryUrl = null;
                            _error = null;
                          });
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Hãy dán lại URL gốc. Lịch sử chỉ giữ địa chỉ máy chủ.',
                              ),
                            ),
                          );
                        },
                      ),
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
              const SectionTitle(
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
              const SectionTitle(Icons.privacy_tip_outlined, 'Quyền riêng tư'),
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

Route<void> _resultRoute(
  Map<String, dynamic> result,
  bool reduceMotion,
  VoidCallback onRecheck,
) => PageRouteBuilder<void>(
  transitionDuration: reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 300),
  reverseTransitionDuration: reduceMotion
      ? Duration.zero
      : const Duration(milliseconds: 220),
  pageBuilder: (context, animation, secondaryAnimation) =>
      ResultPage(result: result, onRecheck: onRecheck),
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
