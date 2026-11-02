import 'dart:async';

import 'package:flutter/widgets.dart';

/// Detects taps from raw touches, so it can never lose to the page swipe or
/// zoom handling below it, and never blocks them.
class PageSurface extends StatefulWidget {
  const PageSurface({super.key, required this.onTap, required this.child});

  /// Called with the tap's position across the width, from 0 to 1.
  final ValueChanged<double> onTap;
  final Widget child;

  @override
  State<PageSurface> createState() => _PageSurfaceState();
}

class _PageSurfaceState extends State<PageSurface> {
  int _down = 0;
  bool _isTap = false;
  Offset _start = Offset.zero;
  DateTime _at = DateTime.now();

  @override
  Widget build(BuildContext context) {
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (e) {
        _down++;
        _isTap = _down == 1;
        _start = e.position;
        _at = DateTime.now();
      },
      onPointerMove: (e) {
        if ((e.position - _start).distance > 18) _isTap = false;
      },
      onPointerCancel: (_) {
        _down = 0;
        _isTap = false;
      },
      onPointerUp: (e) {
        _down = _down > 0 ? _down - 1 : 0;
        if (!_isTap) return;
        _isTap = false;
        if (DateTime.now().difference(_at) >
            const Duration(milliseconds: 500)) {
          return;
        }
        final width = context.size?.width ?? 1;
        final x = e.localPosition.dx / width;
        // After gesture handling for this touch finishes: the page view's own
        // touch tracking would otherwise cancel an animated page turn.
        scheduleMicrotask(() {
          if (mounted) widget.onTap(x);
        });
      },
      child: widget.child,
    );
  }
}
