import 'dart:async';

import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/link.dart';

import 'visuals.dart';

String verdictLabel(String verdict) => switch (verdict) {
  'high' => 'Nguy cơ cao',
  'caution' => 'Cần xác minh',
  'no_signs' => 'Chưa phát hiện dấu hiệu đáng ngờ',
  _ => 'Chưa đủ thông tin',
};

class ResultPage extends StatefulWidget {
  const ResultPage({super.key, required this.result, this.onRecheck});

  final Map<String, dynamic> result;
  final VoidCallback? onRecheck;

  @override
  State<ResultPage> createState() => _ResultPageState();
}

class _ResultPageState extends State<ResultPage> {
  final _addressKey = GlobalKey();
  final _evidenceKey = GlobalKey();
  Timer? _expiryTimer;

  Map<String, dynamic> get result => widget.result;
  Map get _url => result['url'] as Map;
  Map get _threat => result['threat'] as Map;
  Map get _model => result['model'] as Map;
  List<Map> get _urlSignals => (result['signals'] as List)
      .whereType<Map>()
      .where((signal) => signal['source'] == 'url')
      .toList();
  bool get _historical => result['history_redacted'] == true;
  DateTime? get _expiry => DateTime.tryParse(_threat['expires_at'] ?? '');
  bool get _expired =>
      _threat['status'] == 'detected' &&
      !(_expiry?.isAfter(DateTime.now()) ?? false);

  @override
  void initState() {
    super.initState();
    final expiry = _expiry;
    if (_threat['status'] == 'detected' &&
        expiry != null &&
        expiry.isAfter(DateTime.now())) {
      _expiryTimer = Timer(expiry.difference(DateTime.now()), () {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _expiryTimer?.cancel();
    super.dispose();
  }

  void _scrollTo(GlobalKey key) {
    final target = key.currentContext;
    if (target == null) return;
    Scrollable.ensureVisible(
      target,
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 320),
      curve: Curves.easeOutCubic,
    );
  }

  String? get _sourceFinding {
    if (_threat['status'] != 'detected') return null;
    final categories = (_threat['categories'] as List?) ?? const [];
    final category = switch (categories.firstOrNull) {
      'SOCIAL_ENGINEERING' => 'dấu hiệu lừa người dùng (như phishing)',
      'PHISHING' => 'phishing',
      'MALWARE' => 'mã độc',
      'UNWANTED_SOFTWARE' => 'phần mềm không mong muốn',
      _ => 'nguy cơ',
    };
    return '${_threat['source']} đã ghi nhận $category.';
  }

  String _reason(String verdict, List<Map> signals) {
    if (_historical) {
      return 'Đây là bản ghi lần trước. Dán lại URL gốc để kiểm tra hiện tại.';
    }
    if (_expired) return 'Thông tin cảnh báo của nguồn đã hết hiệu lực.';
    if (verdict == 'high') {
      final finding = _sourceFinding;
      return finding == null
          ? result['summary']
          : '$finding Hãy dừng trước khi mở link.';
    }
    if (verdict == 'caution') {
      final rule = signals.where((s) => s['severity'] == 'strong').firstOrNull;
      if (rule?['code'] == 'misleading_userinfo') {
        return 'Phần trước dấu @ dễ gây nhầm lẫn về máy chủ thực tế.';
      }
      if (rule != null) return '${rule['title']}.';
      if (_model['alert'] == true) {
        return 'Mô hình phát hiện mẫu URL cần xác minh.';
      }
    }
    if (verdict == 'no_signs') {
      if (signals.any((s) => s['severity'] == 'weak')) {
        return 'Có dấu hiệu nhẹ trong URL. Chạm Xem bằng chứng để đọc chi tiết.';
      }
      return _threat['status'] == 'skipped'
          ? 'Phân tích địa chỉ chưa thấy dấu hiệu đáng ngờ. Tra cứu nguồn đang tắt.'
          : 'Phân tích địa chỉ chưa thấy dấu hiệu đáng ngờ trong phạm vi kiểm tra.';
    }
    if (signals.any((s) => s['code'] == 'shortener')) {
      return 'Link rút gọn chưa được xác minh địa chỉ đích.';
    }
    if (_threat['partial'] == true) {
      return 'Một phần nguồn chưa trả về kết quả tra cứu.';
    }
    if (const {
      'error',
      'timeout',
      'quota',
      'not_configured',
    }.contains(_threat['status'])) {
      return 'Tra cứu nguồn chưa hoàn tất. Xem trạng thái từng nguồn bên dưới.';
    }
    return result['summary'];
  }

  Future<void> _share(String verdict, String reason, bool archival) async {
    final status = archival ? 'Kết quả lần trước' : verdictLabel(verdict);
    final host = _url['hostname'];
    final date = formatTime(result['checked_at']);
    // The compact reason is derived from fixed text and server signal titles.
    // Share only the server-verified hostname. Never include the original URL.
    final attribution = !archival && verdict == 'high'
        ? '\n${_threat['attribution'] ?? ''}'
        : '';
    try {
      await SharePlus.instance.share(
        ShareParams(
          title: 'Kết quả Lynveris',
          text:
              'Lynveris · $status\nMáy chủ: $host\nKiểm tra lúc $date'
              '\n$reason$attribution',
        ),
      );
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Chưa mở được bảng chia sẻ trên thiết bị.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final archival = _historical || _expired;
    final verdict = archival ? 'insufficient' : result['verdict'] as String;
    final label = archival ? 'Kết quả lần trước' : verdictLabel(verdict);
    final signals = _urlSignals;
    final reason = _reason(verdict, signals);
    final hasShortener = signals.any((s) => s['code'] == 'shortener');
    final canRetry = widget.onRecheck != null;
    final primaryAction = switch (verdict) {
      'high' => (
        Icons.ios_share_rounded,
        'Chia sẻ cảnh báo',
        () => _share(verdict, reason, false),
      ),
      'caution' => (
        Icons.manage_search_rounded,
        'Xem dấu hiệu',
        () => _scrollTo(
          signals.any((s) => s['severity'] == 'strong')
              ? _addressKey
              : _evidenceKey,
        ),
      ),
      'no_signs' => (
        Icons.fact_check_outlined,
        'Xem bằng chứng',
        () => _scrollTo(_evidenceKey),
      ),
      _ when _historical && canRetry => (
        Icons.edit_outlined,
        'Nhập lại URL gốc',
        widget.onRecheck!,
      ),
      _ when canRetry && (_expired || !hasShortener) => (
        Icons.refresh_rounded,
        'Thử lại',
        widget.onRecheck!,
      ),
      _ => (
        Icons.info_outline_rounded,
        'Xem phần chưa xác minh',
        () => _scrollTo(_evidenceKey),
      ),
    };
    return Scaffold(
      appBar: AppBar(
        title: Text(_historical ? 'Kết quả đã lưu' : 'Phiếu kiểm tra'),
      ),
      body: SafeArea(
        child: PageBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _ReportHeader(
                label: label,
                verdict: verdict,
                reason: reason,
                host: _url['hostname'],
                checkedAt: formatTime(result['checked_at']),
                icon: primaryAction.$1,
                action: primaryAction.$2,
                onAction: primaryAction.$3,
              ),
              const SizedBox(height: 14),
              _AddressCard(
                key: _addressKey,
                url: _url,
                historical: _historical,
                signals: signals,
              ),
              const SizedBox(height: 14),
              _EvidenceCard(
                key: _evidenceKey,
                threat: _threat,
                model: _model,
                archival: archival,
                expired: _expired,
                signals: signals,
              ),
              const SizedBox(height: 14),
              if (verdict != 'no_signs' && !archival) ...[
                _nextStep(verdict, hasShortener),
                const SizedBox(height: 14),
              ],
              _technicalDetails(archival),
              if (verdict != 'high') ...[
                const SizedBox(height: 8),
                TextButton.icon(
                  onPressed: () => _share(verdict, reason, archival),
                  icon: const Icon(Icons.ios_share_rounded),
                  label: const Text('Chia sẻ bản tóm tắt'),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _nextStep(String verdict, bool shortener) => SurfaceCard(
    child: InfoRow(
      icon: Icons.assistant_direction_outlined,
      title: 'Việc nên làm tiếp',
      text: switch (verdict) {
        'high' =>
          'Nếu cần kiểm tra tài khoản, hãy vào ứng dụng hoặc trang chính thức.',
        'caution' => 'Kiểm tra người gửi và đối chiếu tên miền qua kênh chính thức trước khi thao tác.',
        _ when shortener => 'Hỏi người gửi địa chỉ đầy đủ để kiểm tra đích.',
        _ => 'Xem trạng thái từng nguồn và kiểm tra lại khi nguồn hoạt động.',
      },
    ),
  );

  Widget _technicalDetails(bool archival) => SurfaceCard(
    padding: const EdgeInsets.symmetric(horizontal: 16),
    child: ExpansionTile(
      tilePadding: EdgeInsets.zero,
      leading: const Icon(Icons.info_outline_rounded, color: teal),
      title: const Text('Chi tiết và giới hạn kiểm tra'),
      childrenPadding: const EdgeInsets.only(bottom: 16),
      expandedCrossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (_model['version'] case final String version)
          Text('Mô hình: $version'),
        if (result['versions'] case final Map versions)
          Text('Bộ đặc trưng URL: ${versions['features']}'),
        if (_threat['feed_received_at'] case final String received)
          Text('Tải danh sách nguồn lúc ${formatTime(received)}'),
        if (_threat['expires_at'] case final String expires)
          Text('Hiệu lực tra cứu đến ${formatTime(expires)}'),
        if (_threat['attribution'] case final String attribution
            when !archival) ...[
          const SizedBox(height: 8),
          Text(attribution),
          Link(
            uri: Uri.parse(
              _threat['source'] == 'OpenPhish Community'
                  ? 'https://openphish.com/phishing_feeds.html'
                  : 'https://developers.google.com/safe-browsing/v4/support',
            ),
            target: LinkTarget.blank,
            builder: (context, followLink) => TextButton(
              onPressed: followLink,
              child: const Text('Thông tin về nguồn cảnh báo'),
            ),
          ),
        ],
        const SizedBox(height: 8),
        for (final text in (result['limitations'] as List).whereType<String>())
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              text,
              style: const TextStyle(color: muted, height: 1.45),
            ),
          ),
      ],
    ),
  );
}

class _ReportHeader extends StatelessWidget {
  const _ReportHeader({
    required this.label,
    required this.verdict,
    required this.reason,
    required this.host,
    required this.checkedAt,
    required this.icon,
    required this.action,
    required this.onAction,
  });

  final String label, verdict, reason, host, checkedAt, action;
  final IconData icon;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final color = verdictColor(verdict);
    final tint = switch (verdict) {
      'high' => const Color(0xFFFFE9EB),
      'caution' => const Color(0xFFFFF0D9),
      'no_signs' => const Color(0xFFE3F6F0),
      _ => const Color(0xFFEAF1F6),
    };
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [tint, Colors.white],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(25),
        border: Border.all(color: color.withValues(alpha: .23)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Glyph(verdictIcon(verdict), size: 43, color: color),
                const SizedBox(width: 12),
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(
                      label,
                      style: TextStyle(
                        color: color,
                        fontSize: 26,
                        height: 1.13,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -.5,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(reason, style: const TextStyle(color: ink, height: 1.45)),
            const SizedBox(height: 12),
            DecoratedBox(
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: .84),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Eyebrow('MÁY CHỦ THỰC TẾ'),
                    const SizedBox(height: 4),
                    SelectableText(
                      host,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: ink,
                        fontWeight: FontWeight.w800,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 9),
            Text(
              'Kiểm tra lúc $checkedAt',
              style: const TextStyle(color: muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: color,
                foregroundColor: Colors.white,
              ),
              onPressed: onAction,
              icon: Icon(icon, size: 19),
              label: Text(action),
            ),
          ],
        ),
      ),
    );
  }
}

class _AddressCard extends StatelessWidget {
  const _AddressCard({
    super.key,
    required this.url,
    required this.historical,
    required this.signals,
  });

  final Map url;
  final bool historical;
  final List<Map> signals;

  @override
  Widget build(BuildContext context) {
    final host = url['hostname'] as String;
    final domain = url['suffix'] == ''
        ? null
        : url['registered_domain'] as String?;
    final unicode = url['unicode_hostname'] as String;
    // Keep the URL as received. Uri.path would normalize some encoded sequences.
    final rawParts = historical
        ? null
        : RegExp(
            r'^https?://[^/?#]+([^?#]*)(\?[^#]*)?(#.*)?$',
            caseSensitive: false,
          ).firstMatch(url['original'] as String);
    final path = rawParts?.group(1);
    final shortener = signals.any((s) => s['code'] == 'shortener');
    final confusables = {
      for (final signal in signals.where((s) => s['code'] == 'brand_homograph'))
        for (final match in RegExp(
          r'U\+([0-9A-F]{4,6})',
        ).allMatches(signal['detail'] as String))
          int.parse(match.group(1)!, radix: 16),
    };
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(Icons.account_tree_outlined, 'Đọc cấu trúc URL'),
          const SizedBox(height: 12),
          if (!historical && url['has_userinfo'] == true)
            const Padding(
              padding: EdgeInsets.only(bottom: 10),
              child: Text(
                'Có phần đứng trước dấu @. Máy chủ thực tế nằm sau dấu @. Nội dung đứng trước @ được ẩn.',
                style: TextStyle(color: Color(0xFF885B12), height: 1.4),
              ),
            ),
          _AddressPart('Máy chủ', host, highlight: domain),
          if (domain != null) _AddressPart('Tên miền đăng ký', domain),
          if (unicode != host)
            _AddressPart('Dạng Unicode', unicode, markedRunes: confusables),
          if (url['port'] case final int port when !historical)
            _AddressPart('Cổng ghi trong URL', '$port'),
          if (historical)
            const Text(
              'Bản lưu giữ địa chỉ máy chủ. Dán lại URL gốc để phân tích đầy đủ.',
              style: TextStyle(color: muted, height: 1.4),
            )
          else if (path != null) ...[
            _AddressPart('Đường dẫn', path.isEmpty ? '/' : path, compact: true),
            if (rawParts?.group(2) != null || rawParts?.group(3) != null)
              const Padding(
                padding: EdgeInsets.only(top: 3),
                child: Text(
                  'Đã ẩn tham số và phần sau dấu # để bảo vệ thông tin riêng tư.',
                  style: TextStyle(color: muted, height: 1.4),
                ),
              ),
          ],
          if (shortener)
            const Padding(
              padding: EdgeInsets.only(top: 10),
              child: Text(
                'Link rút gọn · Chưa xác minh địa chỉ đích.',
                style: TextStyle(
                  color: Color(0xFF885B12),
                  fontWeight: FontWeight.w700,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AddressPart extends StatelessWidget {
  const _AddressPart(
    this.label,
    this.value, {
    this.highlight,
    this.markedRunes = const {},
    this.compact = false,
  });

  final String label, value;
  final String? highlight;
  final Set<int> markedRunes;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final domain = highlight;
    final spans = <TextSpan>[];
    if (markedRunes.isNotEmpty) {
      for (final rune in value.runes) {
        spans.add(
          TextSpan(
            text: String.fromCharCode(rune),
            style: markedRunes.contains(rune)
                ? const TextStyle(
                    color: Color(0xFF885B12),
                    backgroundColor: Color(0xFFFFE4B7),
                    fontWeight: FontWeight.w900,
                  )
                : null,
          ),
        );
      }
    } else if (domain != null &&
        (value == domain || value.endsWith('.$domain'))) {
      spans.add(
        TextSpan(
          text: value.substring(0, value.length - domain.length),
          style: const TextStyle(color: muted),
        ),
      );
      spans.add(
        TextSpan(
          text: domain,
          style: const TextStyle(color: teal, fontWeight: FontWeight.w900),
        ),
      );
    } else {
      spans.add(TextSpan(text: value));
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 3),
          Text.rich(
            TextSpan(children: spans),
            textDirection: TextDirection.ltr,
            maxLines: compact ? 3 : null,
            overflow: compact ? TextOverflow.ellipsis : null,
            style: const TextStyle(
              color: ink,
              height: 1.45,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}

class _EvidenceCard extends StatelessWidget {
  const _EvidenceCard({
    super.key,
    required this.threat,
    required this.model,
    required this.archival,
    required this.expired,
    required this.signals,
  });

  final Map threat, model;
  final bool archival, expired;
  final List<Map> signals;

  @override
  Widget build(BuildContext context) {
    final checks = (threat['checks'] as List? ?? const []).whereType<Map>();
    final visibleChecks = checks.isEmpty ? [threat] : checks;
    final findings = signals.where((s) => s['severity'] != 'info');
    return SurfaceCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SectionTitle(Icons.fact_check_outlined, 'Bằng chứng kiểm tra'),
          const SizedBox(height: 12),
          const Eyebrow('QUY TẮC PHÂN TÍCH URL'),
          if (findings.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 7),
              child: Text(
                'Chưa thấy dấu hiệu đáng ngờ trong cấu trúc địa chỉ.',
              ),
            ),
          for (final signal in [
            ...findings.where((s) => s['severity'] == 'strong'),
            ...findings.where((s) => s['severity'] != 'strong'),
          ])
            InfoRow(
              icon: Icons.link_rounded,
              title: signal['title'],
              text: signal['detail'],
            ),
          const Divider(height: 23),
          const Eyebrow('MÔ HÌNH URL'),
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text(switch (model['status']) {
              'ready' when model['alert'] == true =>
                'Phát hiện mẫu URL cần xác minh.',
              'ready' => 'Không phát cảnh báo từ đặc trưng URL.',
              'error' => 'Mô hình gặp lỗi khi phân tích.',
              _ => 'Mô hình chưa sẵn sàng.',
            }),
          ),
          const Divider(height: 23),
          const Eyebrow('NGUỒN TRA CỨU'),
          for (final check in visibleChecks)
            _SourceRow(check: check, archival: archival, expired: expired),
        ],
      ),
    );
  }
}

class _SourceRow extends StatelessWidget {
  const _SourceRow({
    required this.check,
    required this.archival,
    required this.expired,
  });
  final Map check;
  final bool archival, expired;

  @override
  Widget build(BuildContext context) {
    final status = check['status'];
    final (label, color, icon) = switch (status) {
      'detected' when expired => (
        'Đã hết hiệu lực',
        muted,
        Icons.history_rounded,
      ),
      'detected' when archival => (
        'Từng ghi nhận',
        muted,
        Icons.history_rounded,
      ),
      'detected' => (
        'Đã ghi nhận',
        verdictColor('high'),
        Icons.report_gmailerrorred_rounded,
      ),
      'not_found' => (
        'Chưa ghi nhận',
        muted,
        Icons.remove_circle_outline_rounded,
      ),
      'skipped' => ('Tra cứu đang tắt', muted, Icons.visibility_off_outlined),
      'timeout' => (
        'Chưa tra được · Quá thời gian chờ',
        verdictColor('caution'),
        Icons.timer_off_outlined,
      ),
      'not_configured' => (
        'Chưa tra được · Nguồn chưa cấu hình',
        verdictColor('caution'),
        Icons.cloud_off_outlined,
      ),
      'quota' => (
        'Chưa tra được · Giới hạn lượt',
        verdictColor('caution'),
        Icons.cloud_off_outlined,
      ),
      _ => ('Chưa tra được', verdictColor('caution'), Icons.cloud_off_outlined),
    };
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 9),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${check['source']}',
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                Text(label, style: TextStyle(color: color, height: 1.4)),
                if (check['checked_at'] case final String time)
                  Text(
                    'Tra lúc ${formatTime(time)}',
                    style: const TextStyle(
                      color: muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
