import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../audio/audio_handler.dart';
import '../../audio/chapters.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../library/book_card.dart';
import '../player/player_bar.dart';

/// Built for using without looking: big buttons and little else to hit.
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key, required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);
    final hasChapters = handler.chapters.value.length > 1;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Space.xl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.only(top: Space.s),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      tooltip: 'Back to reading',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 32,
                      ),
                    ),
                    IconButton(
                      tooltip: 'Settings',
                      onPressed: () => openSettings(context),
                      icon: const Icon(Icons.settings_outlined),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: Space.m),
                  child: Center(child: BookCover(book: book, titleSize: 20)),
                ),
              ),
              Text(
                book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.headlineMedium,
              ),
              const SizedBox(height: Space.xs),
              _Subtitle(book: book),
              const SizedBox(height: Space.m),
              const Scrubber(),
              const SizedBox(height: Space.m),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  if (hasChapters)
                    IconButton(
                      tooltip: 'Previous chapter',
                      iconSize: 32,
                      onPressed: handler.previousChapter,
                      icon: const Icon(Icons.skip_previous_rounded),
                    ),
                  SkipButton(forward: false, size: hasChapters ? 52 : 60),
                  PlayButton(size: hasChapters ? 64 : 76),
                  SkipButton(forward: true, size: hasChapters ? 52 : 60),
                  if (hasChapters)
                    IconButton(
                      tooltip: 'Next chapter',
                      iconSize: 32,
                      onPressed: handler.nextChapter,
                      icon: const Icon(Icons.skip_next_rounded),
                    ),
                ],
              ),
              const SizedBox(height: Space.l),
              Row(
                children: [
                  Expanded(
                    child: _Action(
                      icon: Icons.speed_rounded,
                      label: speedLabel(
                        ref.watch(playbackStateProvider).value?.speed ?? 1.0,
                      ),
                      onTap: () => showSpeedSheet(context),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: ValueListenableBuilder(
                      valueListenable: handler.sleep,
                      builder: (context, timer, _) => _Action(
                        icon: Icons.bedtime_outlined,
                        label: _sleepLabel(timer),
                        active: timer != null,
                        onTap: () => showSleepSheet(context),
                      ),
                    ),
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: _Action(
                      icon: Icons.format_list_bulleted_rounded,
                      label: 'Chapters',
                      onTap: () => showAudioChapters(context),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.l),
            ],
          ),
        ),
      ),
    );
  }

  String _sleepLabel(SleepTimer? timer) {
    if (timer == null) return 'Sleep';
    final ends = timer.endsAt;
    if (ends == null) return 'Chapter end';
    final minutes = ends.difference(DateTime.now()).inMinutes + 1;
    return '$minutes min';
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    required this.onTap,
    this.active = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final fg = active ? s.onPrimary : s.onSurface;
    return Bubbly(
      child: Material(
        color: active ? s.primary : s.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(Space.xl),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 22, color: fg),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall
                      ?.copyWith(color: fg),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Subtitle extends ConsumerWidget {
  const _Subtitle({required this.book});

  final Book book;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final list = handler.chapters.value;
    final i = chapterIndexAt(list, position);
    final parts = [
      if (i >= 0) list[i].title,
      if (book.author != null) book.author!,
    ];
    return Text(
      parts.isEmpty ? ' ' : parts.join(' · '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: Theme.of(context).textTheme.bodyMedium
          ?.copyWith(color: context.twofold.muted),
    );
  }
}
