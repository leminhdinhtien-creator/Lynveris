import 'dart:math' as math;

import 'package:flutter/material.dart';

const ink = Color(0xFF111E35);
const night = Color(0xFF0D1730);
const paper = Color(0xFFF2F5FC);
const teal = Color(0xFF135E69);
const aqua = Color(0xFF68F0DA);
const muted = Color(0xFF526078);
const edge = Color(0xFFDEE6F3);
const moon = Color(0xFFBCCDE9);

ThemeData lynverisTheme() {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF347BDB))
      .copyWith(
        primary: night,
        onPrimary: Colors.white,
        surface: Colors.white,
        onSurface: ink,
        onSurfaceVariant: muted,
        outlineVariant: edge,
        secondaryContainer: const Color(0xFFDCEFF7),
        onSecondaryContainer: night,
      );
  final inputBorder = OutlineInputBorder(
    borderRadius: BorderRadius.circular(18),
    borderSide: const BorderSide(color: edge),
  );
  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: paper,
    dividerColor: edge,
    textTheme: ThemeData.light().textTheme.apply(
      bodyColor: ink,
      displayColor: ink,
    ),
    appBarTheme: const AppBarTheme(
      backgroundColor: paper,
      foregroundColor: ink,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
        color: ink,
        fontSize: 19,
        fontWeight: FontWeight.w800,
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 54),
        textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(17)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(48, 50),
        side: const BorderSide(color: edge),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFFF5F8FF),
      contentPadding: const EdgeInsets.all(16),
      border: inputBorder,
      enabledBorder: inputBorder,
      focusedBorder: inputBorder.copyWith(
        borderSide: const BorderSide(color: Color(0xFF3279A7), width: 1.6),
      ),
    ),
    navigationBarTheme: const NavigationBarThemeData(
      height: 68,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      indicatorColor: Color(0xFFD9EFF5),
      labelTextStyle: WidgetStatePropertyAll(
        TextStyle(fontWeight: FontWeight.w700, fontSize: 12),
      ),
    ),
    bottomSheetTheme: const BottomSheetThemeData(
      backgroundColor: paper,
      showDragHandle: true,
    ),
    dialogTheme: const DialogThemeData(backgroundColor: paper),
    snackBarTheme: const SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: night,
      contentTextStyle: TextStyle(color: Colors.white),
    ),
  );
}

class SurfaceCard extends StatelessWidget {
  const SurfaceCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(18),
  });
  final Widget child;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      border: Border.all(color: edge),
      boxShadow: const [
        BoxShadow(
          color: Color(0x080F244D),
          blurRadius: 24,
          offset: Offset(0, 8),
        ),
      ],
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class Glyph extends StatelessWidget {
  const Glyph(this.icon, {super.key, this.color = teal, this.size = 42});
  final IconData icon;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: color.withValues(alpha: .10),
      borderRadius: BorderRadius.circular(size * .32),
    ),
    child: Icon(icon, size: size * .53, color: color),
  );
}

class SignalLabel extends StatelessWidget {
  const SignalLabel(this.text, {super.key, this.color = aqua});
  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: TextStyle(
      color: color,
      fontSize: 10,
      fontWeight: FontWeight.w800,
      letterSpacing: 1.45,
      height: 1.45,
    ),
  );
}

/// The artwork never encodes detections. Its rings and markers are decorative.
class RadarArt extends StatelessWidget {
  const RadarArt({
    super.key,
    required this.size,
    this.color = aqua,
    this.rotation,
    this.icon = Icons.shield_outlined,
  });
  final double size;
  final Color color;
  final Animation<double>? rotation;
  final IconData icon;

  @override
  Widget build(BuildContext context) => ExcludeSemantics(
    child: RepaintBoundary(
      child: SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: _RadarPainter(color, rotation),
          child: Center(
            child: Container(
              width: size * .31,
              height: size * .31,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: night,
                border: Border.all(color: color.withValues(alpha: .75)),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: .24),
                    blurRadius: size * .14,
                  ),
                ],
              ),
              child: Icon(icon, color: color, size: size * .18),
            ),
          ),
        ),
      ),
    ),
  );
}

class _RadarPainter extends CustomPainter {
  _RadarPainter(this.color, this.rotation) : super(repaint: rotation);
  final Color color;
  final Animation<double>? rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide * .40;
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final angle = (rotation?.value ?? .83) * math.pi * 2;
    final glow = Paint()
      ..shader = RadialGradient(
        colors: [color.withValues(alpha: .15), color.withValues(alpha: 0)],
      ).createShader(bounds);
    canvas.drawCircle(center, radius, glow);
    final line = Paint()
      ..color = color.withValues(alpha: .21)
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    for (final ratio in [.43, .68, .99]) {
      canvas.drawCircle(center, radius * ratio, line);
    }
    canvas.drawLine(
      center - Offset(radius, 0),
      center + Offset(radius, 0),
      line,
    );
    canvas.drawLine(
      center - Offset(0, radius),
      center + Offset(0, radius),
      line,
    );
    for (var i = 0; i < 48; i++) {
      final theta = i * math.pi / 24;
      final start = i % 6 == 0 ? 1.04 : 1.09;
      final direction = Offset(math.cos(theta), math.sin(theta));
      canvas.drawLine(
        center + direction * (radius * start),
        center + direction * (radius * 1.15),
        line,
      );
    }
    canvas.save();
    canvas.translate(center.dx, center.dy);
    canvas.rotate(angle);
    final local = Rect.fromCircle(center: Offset.zero, radius: radius);
    final sweep = Paint()
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
          color.withValues(alpha: .40),
        ],
        stops: const [0, .79, 1],
      ).createShader(local);
    canvas.drawCircle(Offset.zero, radius, sweep);
    canvas.drawLine(
      Offset.zero,
      Offset(radius, 0),
      Paint()
        ..color = color.withValues(alpha: .85)
        ..strokeWidth = 1.4,
    );
    canvas.restore();
    for (final point in [const Offset(.65, -.44), const Offset(-.58, .55)]) {
      final position = center + point * radius;
      canvas.drawCircle(
        position,
        5,
        Paint()..color = color.withValues(alpha: .16),
      );
      canvas.drawCircle(position, 2.2, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_RadarPainter oldDelegate) =>
      color != oldDelegate.color || rotation != oldDelegate.rotation;
}

class MissionHeader extends StatelessWidget {
  const MissionHeader({
    super.key,
    required this.label,
    required this.title,
    required this.description,
    this.icon = Icons.shield_outlined,
    this.accent = aqua,
  });
  final String label, title, description;
  final IconData icon;
  final Color accent;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(26),
      gradient: const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [night, Color(0xFF162A55), Color(0xFF12434E)],
      ),
    ),
    child: Stack(
      children: [
        Positioned(
          right: -57,
          bottom: -62,
          child: Opacity(
            opacity: .54,
            child: RadarArt(size: 215, icon: icon, color: accent),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(22, 21, 22, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SignalLabel(label, color: accent),
              const SizedBox(height: 10),
              Text(
                title,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 31,
                  height: 1.11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -.8,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                description,
                style: const TextStyle(color: moon, fontSize: 14, height: 1.5),
              ),
            ],
          ),
        ),
      ],
    ),
  );
}

class ScanPanel extends StatefulWidget {
  const ScanPanel({super.key, required this.host, required this.onBack});
  final String host;
  final VoidCallback onBack;

  @override
  State<ScanPanel> createState() => _ScanPanelState();
}

class _ScanPanelState extends State<ScanPanel>
    with SingleTickerProviderStateMixin {
  late final _rotation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1550),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotation.stop();
    } else if (!_rotation.isAnimating) {
      _rotation.repeat();
    }
  }

  @override
  void dispose() {
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => DecoratedBox(
      decoration: const BoxDecoration(
        gradient: RadialGradient(
          center: Alignment(0, -.25),
          radius: .92,
          colors: [Color(0xFF1E3B65), night],
        ),
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 22),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            minHeight: math.max(0, constraints.maxHeight - 44),
          ),
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SignalLabel('LYNVERIS  /  KIỂM TRA URL'),
                  RadarArt(
                    size: constraints.maxHeight < 470 ? 176 : 242,
                    rotation: MediaQuery.disableAnimationsOf(context)
                        ? null
                        : _rotation,
                  ),
                  Semantics(
                    liveRegion: true,
                    child: const Text(
                      'Đang kiểm tra đường link…',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        height: 1.25,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  if (widget.host.isNotEmpty) ...[
                    const SizedBox(height: 13),
                    Text(
                      widget.host,
                      textAlign: TextAlign.center,
                      textDirection: TextDirection.ltr,
                      style: const TextStyle(
                        color: aqua,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  const Text(
                    'Đang chờ kết quả từ máy chủ.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: moon, height: 1.5),
                  ),
                  const SizedBox(height: 18),
                  TextButton.icon(
                    onPressed: widget.onBack,
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      minimumSize: const Size(48, 48),
                    ),
                    icon: const Icon(Icons.arrow_back_rounded),
                    label: const Text('Quay lại'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}
