import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

/// Squishes while held and springs back with a wobble on release.
class Bubbly extends StatefulWidget {
  const Bubbly({super.key, required this.child, this.squish = 0.9});

  final Widget child;

  /// Scale while pressed. Large things should move less.
  final double squish;

  @override
  State<Bubbly> createState() => _BubblyState();
}

class _BubblyState extends State<Bubbly> with SingleTickerProviderStateMixin {
  static const _spring = SpringDescription(
    mass: 1,
    stiffness: 420,
    damping: 13,
  );

  late final _scale = AnimationController.unbounded(vsync: this, value: 1);

  void _to(double target) {
    if (MediaQuery.disableAnimationsOf(context)) return;
    _scale.animateWith(
      SpringSimulation(_spring, _scale.value, target, _scale.velocity),
    );
  }

  @override
  void dispose() {
    _scale.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
    onPointerDown: (_) => _to(widget.squish),
    onPointerUp: (_) => _to(1),
    onPointerCancel: (_) => _to(1),
    child: ScaleTransition(scale: _scale, child: widget.child),
  );
}

/// The touch effect of every button: a soft bloom with bubbles floating off it.
class BubbleSplashFactory extends InteractiveInkFeatureFactory {
  const BubbleSplashFactory();

  @override
  InteractiveInkFeature create({
    required MaterialInkController controller,
    required RenderBox referenceBox,
    required Offset position,
    required Color color,
    required TextDirection textDirection,
    bool containedInkWell = false,
    RectCallback? rectCallback,
    BorderRadius? borderRadius,
    ShapeBorder? customBorder,
    double? radius,
    VoidCallback? onRemoved,
  }) => _BubbleSplash(
    controller: controller,
    referenceBox: referenceBox,
    position: position,
    color: color,
    textDirection: textDirection,
    clip: containedInkWell
        ? (rectCallback ?? () => Offset.zero & referenceBox.size)
        : null,
    borderRadius: borderRadius,
    customBorder: customBorder,
    onRemoved: onRemoved,
  );
}

class _BubbleSplash extends InteractiveInkFeature {
  _BubbleSplash({
    required MaterialInkController controller,
    required super.referenceBox,
    required this.position,
    required super.color,
    required this.textDirection,
    required this.clip,
    this.borderRadius,
    super.customBorder,
    super.onRemoved,
  }) : super(controller: controller) {
    final random = Random(position.hashCode);
    final size = referenceBox.size;
    _reach = max(size.width, size.height);
    _bubbles = [
      for (var i = 0; i < 7; i++)
        (
          // Mostly upward, like bubbles in a glass.
          angle: -pi / 2 + (random.nextDouble() - 0.5) * pi * 0.9,
          distance: (0.25 + random.nextDouble() * 0.5) * min(_reach, 160.0),
          radius: 1.5 + random.nextDouble() * min(_reach / 16, 5.0),
          delay: random.nextDouble() * 0.25,
        ),
    ];
    _time =
        AnimationController(
            duration: const Duration(milliseconds: 650),
            vsync: controller.vsync,
          )
          ..addListener(controller.markNeedsPaint)
          ..addStatusListener((status) {
            if (status == AnimationStatus.completed) dispose();
          })
          ..forward();
    controller.addInkFeature(this);
  }

  final Offset position;
  final TextDirection textDirection;
  final RectCallback? clip;
  final BorderRadius? borderRadius;

  late final double _reach;
  late final List<
    ({double angle, double distance, double radius, double delay})
  >
  _bubbles;
  late final AnimationController _time;

  @override
  void paintFeature(Canvas canvas, Matrix4 transform) {
    final t = _time.value;
    final eased = Curves.easeOutCubic.transform(t);
    void circle(Offset center, double radius, double alpha) => paintInkCircle(
      canvas: canvas,
      transform: transform,
      paint: Paint()..color = color.withValues(alpha: alpha.clamp(0.0, 1.0)),
      center: center,
      textDirection: textDirection,
      radius: radius,
      customBorder: customBorder,
      borderRadius: borderRadius ?? BorderRadius.zero,
      clipCallback: clip,
    );

    circle(position, _reach * eased, color.a * (1 - t));
    final strong = min(color.a * 3, 0.7);
    for (final b in _bubbles) {
      final local = ((t - b.delay) / (1 - b.delay)).clamp(0.0, 1.0);
      if (local == 0) continue;
      final travel = Curves.easeOut.transform(local) * b.distance;
      final center = position + Offset(cos(b.angle), sin(b.angle)) * travel;
      // Grows a little, then pops.
      circle(center, b.radius * (0.6 + local * 0.6), strong * (1 - local));
    }
  }

  @override
  void dispose() {
    _time.dispose();
    super.dispose();
  }
}

/// A progress line that waves, as Material's expressive indicators do.
class WavyProgress extends StatelessWidget {
  const WavyProgress({
    super.key,
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 10,
    child: CustomPaint(
      size: Size.infinite,
      painter: _WavePainter(value.clamp(0.0, 1.0), color, track),
    ),
  );
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.value, this.color, this.track);

  final double value;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    Paint stroke(Color c) => Paint()
      ..color = c
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    final mid = size.height / 2;
    final split = size.width * value;
    if (split < size.width - 6) {
      canvas.drawLine(
        Offset(max(split + 6, 2), mid),
        Offset(size.width - 2, mid),
        stroke(track),
      );
    }
    if (split < 3) return;
    final wave = Path()..moveTo(2, mid);
    for (var x = 2.0; x <= split; x += 1) {
      wave.lineTo(x, mid + sin(x / 24 * 2 * pi) * 2.5);
    }
    canvas.drawPath(wave, stroke(color));
  }

  @override
  bool shouldRepaint(_WavePainter old) =>
      old.value != value || old.color != color || old.track != track;
}
