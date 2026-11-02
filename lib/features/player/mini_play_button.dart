import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';

/// Small round control on the page's footer, in a 48 dp target. Quiet enough to
/// read beside, and easy to hit without looking.
class _MiniButton extends StatelessWidget {
  const _MiniButton({
    required this.label,
    required this.onTap,
    required this.child,
    this.filled = false,
  });

  final String label;
  final VoidCallback onTap;
  final Widget child;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = context.twofold;
    return Semantics(
      button: true,
      label: label,
      child: Bubbly(
        squish: 0.82,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: Space.minTarget,
            height: Space.minTarget,
            child: Center(
              child: Container(
                width: 40,
                height: 40,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: filled
                      ? c.accent
                      : Theme.of(context).colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class MiniPlayButton extends ConsumerWidget {
  const MiniPlayButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    return _MiniButton(
      label: playing ? 'Pause' : 'Play',
      filled: true,
      onTap: playing ? handler.pause : handler.play,
      child: Icon(
        playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
        size: 22,
        color: Theme.of(context).colorScheme.onPrimary,
      ),
    );
  }
}

/// The "I missed that" button, always one tap away while reading.
class MiniBackButton extends ConsumerWidget {
  const MiniBackButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final c = context.twofold;
    final seconds = handler.skipLength.inSeconds;
    return _MiniButton(
      label: 'Back $seconds seconds',
      onTap: () {
        HapticFeedback.lightImpact();
        handler.rewind();
      },
      child: Stack(
        alignment: Alignment.center,
        children: [
          Icon(Icons.replay_rounded, size: 28, color: c.text),
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              '$seconds',
              style: TextStyle(
                fontFamily: uiFont,
                fontSize: 9,
                fontWeight: FontWeight.w500,
                color: c.text,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
