import 'package:flutter/material.dart';

/// A quiet press: the control settles back a touch while held, with no
/// bounce. [squish] is kept for callers; it is softened so nothing jumps.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.squish = 0.97});

  final Widget child;

  /// Scale while pressed. Values below 0.96 are treated as 0.96.
  final double squish;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool down) {
    if (MediaQuery.disableAnimationsOf(context) || down == _down) return;
    setState(() => _down = down);
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _set(true),
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          scale: _down ? widget.squish.clamp(0.96, 1.0) : 1,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut,
          child: widget.child,
        ),
      );
}

/// A thin, straight reading-progress line, like a bookmark ribbon.
class ProgressLine extends StatelessWidget {
  const ProgressLine({
    super.key,
    required this.value,
    required this.color,
    required this.track,
  });

  final double value;
  final Color color;
  final Color track;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(2),
        child: SizedBox(
          height: 3,
          child: Stack(
            children: [
              Positioned.fill(child: ColoredBox(color: track)),
              FractionallySizedBox(
                widthFactor: value.clamp(0.0, 1.0),
                heightFactor: 1,
                child: ColoredBox(color: color),
              ),
            ],
          ),
        ),
      );
}
