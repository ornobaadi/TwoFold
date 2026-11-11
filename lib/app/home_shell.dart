import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/player_controller.dart';
import '../features/find/find_screen.dart';
import '../features/library/book_card.dart';
import '../features/library/library_screen.dart';
import '../features/library/providers.dart';
import '../features/player/player_bar.dart';
import '../features/settings/settings_screen.dart';
import 'format.dart';
import 'press.dart';
import 'router.dart';
import 'theme.dart';

/// Shelf, Find and Settings behind one dock, with what's playing above it.
/// Each tab keeps its place (scroll, search, open list) while another shows.
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key, this.resumeBookId, this.initialTab = 0});

  final String? resumeBookId;
  final int initialTab;

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  late int _tab = widget.initialTab;

  @override
  void initState() {
    super.initState();
    // Parts Android saved while the app was closed are taken in, and saving
    // carries on.
    ref.read(downloadsProvider).refresh().catchError((_) {});
  }

  void _go(int tab) {
    if (tab == _tab) return;
    // Books found in Find show up on the shelf straight away.
    if (tab == 0) ref.invalidate(libraryProvider);
    setState(() => _tab = tab);
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Back from Settings returns to the shelf; Find handles its own back.
      canPop: _tab == 0,
      onPopInvokedWithResult: (popped, _) {
        if (!popped && _tab == 2) _go(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: _tab,
          children: [
            LibraryScreen(
              resumeBookId: widget.resumeBookId,
              onFind: () => _go(1),
            ),
            FindScreen(active: _tab == 1, onExit: () => _go(0)),
            const SettingsScreen(),
          ],
        ),
        bottomNavigationBar: _Dock(tab: _tab, onTab: _go),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.tab, required this.onTab});

  final int tab;
  final ValueChanged<int> onTab;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return Material(
      color: s.surface,
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const NowPlayingStrip(),
            Divider(height: 1, thickness: 1, color: s.outlineVariant),
            SizedBox(
              height: 60,
              child: Row(
                children: [
                  _DockItem(
                    icon: Icons.auto_stories_outlined,
                    selectedIcon: Icons.auto_stories_rounded,
                    label: 'Shelf',
                    selected: tab == 0,
                    onTap: () => onTab(0),
                  ),
                  _DockItem(
                    icon: Icons.travel_explore_rounded,
                    selectedIcon: Icons.travel_explore_rounded,
                    label: 'Find',
                    selected: tab == 1,
                    onTap: () => onTab(1),
                  ),
                  _DockItem(
                    icon: Icons.tune_rounded,
                    selectedIcon: Icons.tune_rounded,
                    label: 'Settings',
                    selected: tab == 2,
                    onTap: () => onTab(2),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  const _DockItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final color = selected ? s.onSurface : s.onSurfaceVariant;
    return Expanded(
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        excludeSemantics: true,
        child: InkWell(
          onTap: onTap,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(selected ? selectedIcon : icon, size: 22, color: color),
              const SizedBox(height: 2),
              Text(
                label,
                style: theme.textTheme.labelSmall?.copyWith(
                  color: color,
                  fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
              const SizedBox(height: 3),
              // A short ink rule under the chosen tab; no tinted pill.
              AnimatedContainer(
                duration: easeDuration,
                curve: easeCurve,
                width: selected ? 16 : 0,
                height: 2,
                color: s.onSurface,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The loaded book's audio, one tap from anywhere at home. Opens Listen.
class NowPlayingStrip extends ConsumerWidget {
  const NowPlayingStrip({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final item = ref.watch(mediaItemProvider).value;
    if (item == null) return const SizedBox.shrink();
    final entries = ref.watch(libraryProvider).value ?? const <LibraryEntry>[];
    LibraryEntry? entry;
    for (final e in entries) {
      if (e.book.id == item.id) entry = e;
    }
    if (entry == null) return const SizedBox.shrink();
    final book = entry.book;

    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final total = item.duration ?? Duration.zero;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;
    final fraction = total > Duration.zero
        ? (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0)
        : 0.0;
    final left = total - position;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Divider(height: 1, thickness: 1, color: s.outlineVariant),
        Semantics(
          button: true,
          label:
              'Now ${playing ? 'playing' : 'paused'}: ${book.title}. Open the player.',
          child: InkWell(
            onTap: () => openListen(context, book),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.s,
                Space.xs,
                Space.s,
              ),
              child: Row(
                children: [
                  SizedBox(
                    width: 30,
                    child: ExcludeSemantics(
                      child: BookCover(book: book, titleSize: 5),
                    ),
                  ),
                  const SizedBox(width: Space.m),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                        Text(
                          total > Duration.zero
                              ? '${formatTime(left)} left'
                              : (book.author ?? ''),
                          maxLines: 1,
                          style: theme.textTheme.bodySmall,
                        ),
                        const SizedBox(height: 4),
                        ProgressLine(
                          value: fraction,
                          color: s.primary,
                          track: s.onSurface.withValues(alpha: 0.12),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: Space.s),
                  const SkipButton(forward: false, size: 36),
                  const SizedBox(width: Space.xs),
                  const SizedBox(
                    width: Space.minTarget,
                    height: Space.minTarget,
                    child: Center(child: PlayButton(size: 40)),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
