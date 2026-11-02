import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
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

/// The app's colour, as round blobs that puff up when chosen.
class PaletteChooser extends ConsumerWidget {
  const PaletteChooser({super.key, this.scrolling = false});

  /// One swipeable row, for tight spaces. Otherwise all of them in a grid.
  final bool scrolling;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final dots = [
      for (final p in AppPalette.values)
        _PaletteDot(
          palette: p,
          dark: Theme.of(context).brightness == Brightness.dark,
          selected: s.palette == p,
          onTap: () => notifier.change(s.copyWith(palette: p)),
        ),
    ];
    if (scrolling) {
      return SizedBox(
        height: 88,
        child: ListView.separated(
          scrollDirection: Axis.horizontal,
          itemCount: dots.length,
          separatorBuilder: (_, _) => const SizedBox(width: Space.xs),
          itemBuilder: (_, i) => dots[i],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, box) {
        final width = (box.maxWidth - Space.xs * 3) / 4;
        return Wrap(
          spacing: Space.xs,
          runSpacing: Space.s,
          children: [for (final d in dots) SizedBox(width: width, child: d)],
        );
      },
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
    final look = schemeFor(
      dark ? ReaderTheme.night : ReaderTheme.paper,
      palette,
    );
    return Semantics(
      button: true,
      selected: selected,
      label: '${palette.label} colour',
      excludeSemantics: true,
      child: Bubbly(
        squish: 0.82,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            width: 68,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  height: 60,
                  child: Center(
                    child: AnimatedContainer(
                      duration: springDuration,
                      curve: springCurve,
                      width: selected ? 58 : 48,
                      height: selected ? 58 : 48,
                      clipBehavior: Clip.antiAlias,
                      decoration: BoxDecoration(
                        color: look.primary,
                        borderRadius: BorderRadius.circular(selected ? 20 : 24),
                      ),
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned(
                            right: -10,
                            bottom: -10,
                            child: Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: look.tertiary,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          if (selected)
                            Icon(Icons.check_rounded, color: look.onPrimary),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  palette.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Auto, Paper, Sepia and Night, each drawn in its own colours.
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

  @override
  Widget build(BuildContext context) {
    final look = schemeFor(
      theme == ReaderTheme.system ? ReaderTheme.paper : theme,
      palette,
    );
    final name = switch (theme) {
      ReaderTheme.system => 'Auto',
      ReaderTheme.paper => 'Paper',
      ReaderTheme.sepia => 'Sepia',
      ReaderTheme.night => 'Night',
    };
    final primary = Theme.of(context).colorScheme.primary;
    return Semantics(
      button: true,
      selected: selected,
      label: '$name theme',
      excludeSemantics: true,
      child: Bubbly(
        child: GestureDetector(
          onTap: onTap,
          child: AnimatedContainer(
            duration: springDuration,
            curve: springCurve,
            height: 64,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: look.surface,
              borderRadius: BorderRadius.circular(selected ? 28 : 16),
              border: Border.all(
                color: selected
                    ? primary
                    : Theme.of(context).colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: Text(
              name,
              style: TextStyle(
                fontFamily: serifFont,
                fontSize: 15,
                fontWeight: FontWeight.w500,
                color: look.onSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
