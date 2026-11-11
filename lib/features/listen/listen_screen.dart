import '../../app/mode_switch.dart';
import '../reader/reader_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/press.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../audio/audio_handler.dart';
import '../../audio/chapters.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../library/book_card.dart';
import 'save_status.dart';
import '../player/player_bar.dart';

/// Built for using without looking: big buttons and little else to hit.
class ListenScreen extends ConsumerWidget {
  const ListenScreen({super.key, required this.book, this.fromReader = false});

  final Book book;

  /// Opened from the reader, so Read goes back to it.
  final bool fromReader;

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
                      tooltip: 'Back',
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        size: 28,
                      ),
                    ),
                    ModeSwitch(
                      reading: false,
                      onListen: () {},
                      onRead: () {
                        if (fromReader) {
                          Navigator.of(context).pop();
                        } else {
                          Navigator.of(context).pushReplacement(
                            fadeRoute(ReaderScreen(book: book)),
                          );
                        }
                      },
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
                  child: Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 220),
                      child: BookCover(book: book, titleSize: 15),
                    ),
                  ),
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
              SaveStatus(bookId: book.id, compact: true),
              const SizedBox(height: Space.s),
              const Scrubber(),
              // A part that can't play yet (offline and not saved).
              ValueListenableBuilder(
                valueListenable: handler.playError,
                builder: (context, error, _) => error == null
                    ? const SizedBox.shrink()
                    : Padding(
                        padding: const EdgeInsets.only(top: Space.xs),
                        child: Text(
                          error,
                          textAlign: TextAlign.center,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                      ),
              ),
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
                  SkipButton(forward: false, size: hasChapters ? 44 : 48),
                  PlayButton(size: hasChapters ? 56 : 64),
                  SkipButton(forward: true, size: hasChapters ? 44 : 48),
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
    return Pressable(
      child: Material(
        color: active ? s.primary : s.surfaceContainer,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: 52,
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
