import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/settings.dart';
import '../../app/theme.dart';

void showSettingsSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const SettingsSheet(),
);

/// How the page looks, from inside the reader.
class SettingsSheet extends ConsumerWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final theme = Theme.of(context);

    Widget label(String text) => Padding(
      padding: const EdgeInsets.only(top: Space.xl, bottom: Space.s),
      child: Text(text, style: theme.textTheme.titleSmall),
    );

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Text and colours', style: theme.textTheme.titleLarge),
            const SizedBox(height: Space.l),
            const PaletteChooser(scrolling: true),
            const SizedBox(height: Space.m),
            const ThemeChooser(),
            label('Text size'),
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Smaller text',
                  iconSize: 28,
                  style: IconButton.styleFrom(minimumSize: const Size(64, 56)),
                  onPressed: s.fontSize > 12
                      ? () => notifier.change(
                          s.copyWith(fontSize: s.fontSize - 1),
                        )
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    '${s.fontSize}',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.headlineMedium,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Larger text',
                  iconSize: 28,
                  style: IconButton.styleFrom(minimumSize: const Size(64, 56)),
                  onPressed: s.fontSize < 32
                      ? () => notifier.change(
                          s.copyWith(fontSize: s.fontSize + 1),
                        )
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            label('Font'),
            SegmentedButton<ReadingFont>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(
                  value: ReadingFont.serif,
                  label: Text(
                    'Literata',
                    style: TextStyle(fontFamily: serifFont),
                  ),
                ),
                ButtonSegment(
                  value: ReadingFont.sans,
                  label: Text('Inter', style: TextStyle(fontFamily: uiFont)),
                ),
              ],
              selected: {s.font},
              onSelectionChanged: (v) =>
                  notifier.change(s.copyWith(font: v.first)),
            ),
            label('Line spacing'),
            SegmentedButton<double>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 1.35, label: Text('Tight')),
                ButtonSegment(value: 1.55, label: Text('Normal')),
                ButtonSegment(value: 1.8, label: Text('Loose')),
              ],
              selected: {s.lineHeight},
              onSelectionChanged: (v) =>
                  notifier.change(s.copyWith(lineHeight: v.first)),
            ),
          ],
        ),
      ),
    );
  }
}

/// The accent: five quiet colours as small dots, with their names.
class PaletteChooser extends ConsumerWidget {
  const PaletteChooser({super.key, this.scrolling = false});

  /// Kept for callers; five dots always fit in one row.
  final bool scrolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        for (final p in AppPalette.values)
          Expanded(
            child: _PaletteDot(
              palette: p,
              dark: dark,
              selected: s.palette == p,
              onTap: () => notifier.change(s.copyWith(palette: p)),
            ),
          ),
      ],
    );
  }
}

class _PaletteDot extends StatelessWidget {
  const _PaletteDot({
    required this.palette,
    required this.dark,
    required this.selected,
    required this.onTap,
  });

  final AppPalette palette;
  final bool dark;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final look = schemeFor(dark ? ReaderTheme.night : ReaderTheme.paper, palette);
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.label} colour',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: Space.s),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: easeDuration,
                curve: easeCurve,
                width: 36,
                height: 36,
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: selected ? theme.colorScheme.onSurface : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(color: look.primary, shape: BoxShape.circle),
                ),
              ),
              const SizedBox(height: Space.xs),
              Text(
                palette.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Auto, Paper, Sepia and Night, each shown as a small page in its colours.
class ThemeChooser extends ConsumerWidget {
  const ThemeChooser({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    return Row(
      children: [
        for (final t in ReaderTheme.values) ...[
          Expanded(
            child: _Swatch(
              theme: t,
              palette: s.palette,
              selected: s.theme == t,
              onTap: () => notifier.change(s.copyWith(theme: t)),
            ),
          ),
          if (t != ReaderTheme.values.last) const SizedBox(width: Space.s),
        ],
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.theme,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final ReaderTheme theme;
  final AppPalette palette;
  final bool selected;
  final VoidCallback onTap;

  Widget _page(ColorScheme look) => ColoredBox(
        color: look.surface,
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Aa',
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: TextStyle(
                  fontFamily: serifFont,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: look.onSurface,
                ),
              ),
              const Spacer(),
              for (final w in const [1.0, 0.8, 0.9])
                Padding(
                  padding: const EdgeInsets.only(top: 3),
                  child: FractionallySizedBox(
                    widthFactor: w,
                    child: Container(height: 2, color: look.onSurface.withValues(alpha: 0.35)),
                  ),
                ),
              const SizedBox(height: 5),
              Container(width: 18, height: 3, color: look.primary),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final ui = Theme.of(context);
    final name = switch (theme) {
      ReaderTheme.system => 'Auto',
      ReaderTheme.paper => 'Paper',
      ReaderTheme.sepia => 'Sepia',
      ReaderTheme.night => 'Night',
    };
    final page = theme == ReaderTheme.system
        // Auto: half day, half night.
        ? Row(
            children: [
              Expanded(child: _page(schemeFor(ReaderTheme.paper, palette))),
              Expanded(child: _page(schemeFor(ReaderTheme.night, palette))),
            ],
          )
        : _page(schemeFor(theme, palette));
    return Semantics(
      button: true,
      selected: selected,
      label: '$name theme',
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(
          children: [
            AnimatedContainer(
              duration: easeDuration,
              curve: easeCurve,
              height: 100,
              // The page is clipped to the same corners and the border is
              // drawn over it, so the outline stays even when selected.
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: selected
                      ? ui.colorScheme.onSurface
                      : ui.colorScheme.outlineVariant,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: page,
              ),
            ),
            const SizedBox(height: Space.xs),
            Text(
              name,
              style: ui.textTheme.labelMedium?.copyWith(
                color: ui.colorScheme.onSurface,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
