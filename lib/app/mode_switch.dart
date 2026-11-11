import 'package:flutter/material.dart';

/// Read | Listen, at the top of a book that has audio.
class ModeSwitch extends StatelessWidget {
  const ModeSwitch({
    super.key,
    required this.reading,
    required this.onRead,
    required this.onListen,
    this.playing = false,
  });

  /// The book is playing: Listen shows a live mark, so reading never hides
  /// that audio is running.
  final bool playing;

  final bool reading;
  final VoidCallback onRead;
  final VoidCallback onListen;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    Widget side(String label, bool on, VoidCallback tap) => Semantics(
      button: true,
      selected: on,
      label: label == 'Listen' && playing ? 'Listen, playing' : label,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on ? null : tap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 20),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: on ? s.onSurface : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (label == 'Listen' && playing && !on) ...[
                Icon(Icons.graphic_eq_rounded, size: 16, color: s.primary),
                const SizedBox(width: 6),
              ],
              Text(
                label,
                style: theme.textTheme.labelLarge?.copyWith(
                  color: on ? s.surface : s.onSurface,
                  fontWeight: on ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(21),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          side('Read', reading, onRead),
          side('Listen', !reading, onListen),
        ],
      ),
    );
  }
}
