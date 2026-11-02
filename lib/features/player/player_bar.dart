import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../audio/audio_handler.dart';
import '../../audio/chapters.dart';
import '../../audio/player_controller.dart';
import '../../audio/scrub_guard.dart';

/// The hero control. Round when paused, squared off while playing, so its
/// state can be read at a glance.
class PlayButton extends ConsumerWidget {
  const PlayButton({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final s = Theme.of(context).colorScheme;
    final playing = ref.watch(playbackStateProvider).value?.playing ?? false;

    return Semantics(
      button: true,
      label: playing ? 'Pause' : 'Play',
      child: Bubbly(
        squish: 0.86,
        child: GestureDetector(
          onTap: playing ? handler.pause : handler.play,
          child: AnimatedContainer(
            duration: springDuration,
            curve: springCurve,
            width: size * 1.3,
            height: size,
            decoration: BoxDecoration(
              color: s.primary,
              borderRadius: BorderRadius.circular(
                playing ? size * 0.3 : size / 2,
              ),
            ),
            child: Icon(
              playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
              size: size * 0.56,
              color: s.onPrimary,
            ),
          ),
        ),
      ),
    );
  }
}

/// Circular arrow with the skip length inside, on a tonal button.
class SkipButton extends ConsumerWidget {
  const SkipButton({super.key, required this.forward, this.size = 56});

  final bool forward;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final s = Theme.of(context).colorScheme;
    final seconds = handler.skipLength.inSeconds;
    final icon = Icon(
      Icons.replay_rounded,
      size: size * 0.72,
      color: s.onSecondaryContainer,
    );
    return Semantics(
      button: true,
      label: '${forward ? 'Forward' : 'Back'} $seconds seconds',
      child: Bubbly(
        child: Material(
          color: s.secondaryContainer,
          borderRadius: BorderRadius.circular(size * 0.36),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: () {
              if (forward) {
                handler.fastForward();
              } else {
                HapticFeedback.lightImpact();
                handler.rewind();
              }
            },
            child: SizedBox(
              width: size,
              height: size,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  forward ? Transform.flip(flipX: true, child: icon) : icon,
                  Padding(
                    padding: const EdgeInsets.only(top: 3),
                    child: Text(
                      '$seconds',
                      style: TextStyle(
                        fontFamily: uiFont,
                        fontSize: size * 0.2,
                        fontWeight: FontWeight.w600,
                        color: s.onSecondaryContainer,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Where chapters begin along the whole book, from 0 to 1. The first chapter
/// has no mark. Marks that would touch are dropped, so a book with hundreds of
/// short chapters stays readable.
List<double> chapterMarks(
  List<AudioChapter> chapters,
  Duration total,
  double width,
) {
  if (total <= Duration.zero || width <= 0) return const [];
  const minGap = 4.0;
  final out = <double>[];
  var last = -minGap;
  for (final c in chapters) {
    if (c.start <= Duration.zero || c.start >= total) continue;
    final f = c.start.inMilliseconds / total.inMilliseconds;
    if (f * width - last < minGap) continue;
    out.add(f);
    last = f * width;
  }
  return out;
}

/// A thick rounded track, split at the thumb, with a thin cut at each chapter.
class _ChapterTrack extends SliderTrackShape with BaseSliderTrackShape {
  const _ChapterTrack(this.chapters, this.total, this.cut);

  final List<AudioChapter> chapters;
  final Duration total;
  final Color cut;

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 0,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
    );
    final canvas = context.canvas;
    const gap = 6.0;
    final radius = Radius.circular(rect.height / 2);
    const inner = Radius.circular(2);
    final leftEnd = thumbCenter.dx - gap;
    final rightStart = thumbCenter.dx + gap;
    if (leftEnd > rect.left) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          rect.left,
          rect.top,
          leftEnd,
          rect.bottom,
          topLeft: radius,
          bottomLeft: radius,
          topRight: inner,
          bottomRight: inner,
        ),
        Paint()..color = sliderTheme.activeTrackColor!,
      );
    }
    if (rightStart < rect.right) {
      canvas.drawRRect(
        RRect.fromLTRBAndCorners(
          rightStart,
          rect.top,
          rect.right,
          rect.bottom,
          topRight: radius,
          bottomRight: radius,
          topLeft: inner,
          bottomLeft: inner,
        ),
        Paint()..color = sliderTheme.inactiveTrackColor!,
      );
    }
    final cutPaint = Paint()..color = cut;
    for (final f in chapterMarks(chapters, total, rect.width)) {
      final x = rect.left + f * rect.width;
      if ((x - thumbCenter.dx).abs() < gap) continue;
      canvas.drawRect(
        Rect.fromLTRB(x - 1, rect.top, x + 1, rect.bottom),
        cutPaint,
      );
    }
  }
}

/// Whole-book scrubber with elapsed and total time.
class Scrubber extends ConsumerStatefulWidget {
  const Scrubber({super.key, this.onSurface});

  final Color? onSurface;

  @override
  ConsumerState<Scrubber> createState() => _ScrubberState();
}

class _ScrubberState extends ConsumerState<Scrubber> {
  final _guard = ScrubGuard();
  double? _dragging;

  // After a seek the thumb holds at the target until playback reports it, so
  // it doesn't jump back and forth.
  double? _settling;
  Timer? _settleTimer;

  Duration? _refused;
  Timer? _refusedTimer;

  @override
  void dispose() {
    _settleTimer?.cancel();
    _refusedTimer?.cancel();
    super.dispose();
  }

  Future<void> _finish(double value) async {
    final handler = ref.read(audioHandlerProvider);
    final target = Duration(milliseconds: value.round());
    final allowed = _guard.allow(
      handler.absolutePosition,
      target,
      handler.chapters.value,
      DateTime.now(),
    );
    _refusedTimer?.cancel();
    if (!allowed) {
      HapticFeedback.selectionClick();
      setState(() {
        _dragging = null;
        _refused = target;
      });
      _refusedTimer = Timer(_guard.window, () {
        _guard.reset();
        if (mounted) setState(() => _refused = null);
      });
      return;
    }
    setState(() {
      _dragging = null;
      _refused = null;
      _settling = value;
    });
    _settleTimer?.cancel();
    _settleTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _settling = null);
    });
    await handler.seek(target);
  }

  @override
  Widget build(BuildContext context) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);
    final c = context.twofold;
    // Cuts read as gaps in the track, on whatever surface it sits on.
    final cut = widget.onSurface ?? theme.colorScheme.surface;
    final total = ref.watch(mediaItemProvider).value?.duration ?? Duration.zero;
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final maxMs = total.inMilliseconds <= 0
        ? 1.0
        : total.inMilliseconds.toDouble();

    final settling = _settling;
    if (settling != null && (position.inMilliseconds - settling).abs() < 1500) {
      _settling = null;
      _settleTimer?.cancel();
    }
    final ms = _dragging ?? _settling ?? position.inMilliseconds.toDouble();
    final refused = _refused;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 44,
          child: ValueListenableBuilder(
            valueListenable: handler.chapters,
            builder: (context, chapters, _) => SliderTheme(
              data: SliderTheme.of(context).copyWith(
                padding: EdgeInsets.zero,
                trackHeight: 14,
                thumbSize: const WidgetStatePropertyAll(Size(4, 40)),
                trackShape: _ChapterTrack(chapters, total, cut),
              ),
              child: Slider(
                value: ms.clamp(0.0, maxMs),
                max: maxMs,
                semanticFormatterCallback: (v) =>
                    formatTime(Duration(milliseconds: v.round())),
                onChanged: (v) => setState(() => _dragging = v),
                onChangeEnd: _finish,
              ),
            ),
          ),
        ),
        Row(
          children: [
            Text(
              formatTime(Duration(milliseconds: ms.round())),
              style: theme.textTheme.labelMedium,
            ),
            Expanded(
              child: refused == null
                  ? const SizedBox.shrink()
                  : Text(
                      'Tap again to jump to ${formatTime(refused)}',
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: c.accent,
                      ),
                    ),
            ),
            Text(formatTime(total), style: theme.textTheme.labelMedium),
          ],
        ),
      ],
    );
  }
}

String speedLabel(double speed) {
  final s = speed.toStringAsFixed(2);
  return '${s.endsWith('0') ? s.substring(0, s.length - 1) : s}×';
}

class SpeedButton extends ConsumerWidget {
  const SpeedButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final speed = ref.watch(playbackStateProvider).value?.speed ?? 1.0;
    return TextButton(
      onPressed: () => showSpeedSheet(context),
      style: TextButton.styleFrom(padding: EdgeInsets.zero),
      child: Text(speedLabel(speed), maxLines: 1, softWrap: false),
    );
  }
}

void showSpeedSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const _SpeedSheet(),
);

class _SpeedSheet extends ConsumerWidget {
  const _SpeedSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final speed = ref.watch(playbackStateProvider).value?.speed ?? 1.0;
    final theme = Theme.of(context);
    const presets = [1.0, 1.25, 1.5, 2.0];
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                IconButton.filledTonal(
                  tooltip: 'Slower',
                  iconSize: 28,
                  style: IconButton.styleFrom(minimumSize: const Size(64, 56)),
                  onPressed: speed > minSpeed
                      ? () => handler.setSpeed(speed - 0.05)
                      : null,
                  icon: const Icon(Icons.remove_rounded),
                ),
                Expanded(
                  child: Text(
                    speedLabel(speed),
                    textAlign: TextAlign.center,
                    style: theme.textTheme.displaySmall,
                  ),
                ),
                IconButton.filledTonal(
                  tooltip: 'Faster',
                  iconSize: 28,
                  style: IconButton.styleFrom(minimumSize: const Size(64, 56)),
                  onPressed: speed < maxSpeed
                      ? () => handler.setSpeed(speed + 0.05)
                      : null,
                  icon: const Icon(Icons.add_rounded),
                ),
              ],
            ),
            const SizedBox(height: Space.xl),
            SegmentedButton<double>(
              showSelectedIcon: false,
              emptySelectionAllowed: true,
              segments: [
                for (final p in presets)
                  ButtonSegment(value: p, label: Text(speedLabel(p))),
              ],
              selected: {
                for (final p in presets)
                  if ((speed - p).abs() < 0.01) p,
              },
              onSelectionChanged: (v) {
                if (v.isNotEmpty) handler.setSpeed(v.first);
              },
            ),
          ],
        ),
      ),
    );
  }
}

void showSleepSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  builder: (_) => const _SleepSheet(),
);

class _SleepSheet extends ConsumerWidget {
  const _SleepSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    void done(VoidCallback act) {
      act();
      Navigator.of(context).pop();
    }

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const SheetTitle('Sleep timer'),
          for (final m in const [15, 30, 60])
            ListTile(
              title: Text('$m minutes'),
              onTap: () => done(() => handler.sleepAfter(Duration(minutes: m))),
            ),
          ListTile(
            title: const Text('End of chapter'),
            onTap: () => done(handler.sleepAtChapterEnd),
          ),
          if (handler.sleep.value != null)
            ListTile(
              title: const Text('Turn off'),
              onTap: () => done(handler.cancelSleep),
            ),
        ],
      ),
    );
  }
}

class SheetTitle extends StatelessWidget {
  const SheetTitle(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.s),
    child: Text(text, style: Theme.of(context).textTheme.titleLarge),
  );
}

void showAudioChapters(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  isScrollControlled: true,
  builder: (_) => const _ChaptersSheet(),
);

class _ChaptersSheet extends ConsumerWidget {
  const _ChaptersSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final list = handler.chapters.value;
    final current = chapterIndexAt(list, handler.absolutePosition);
    final theme = Theme.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.7,
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SheetTitle('Chapters'),
            if (list.isEmpty)
              Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Text(
                  'This audio has no chapters.',
                  style: theme.textTheme.bodyMedium,
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: list.length,
                  itemBuilder: (context, i) => ListTile(
                    title: Text(
                      list[i].title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: i == current ? context.twofold.accent : null,
                      ),
                    ),
                    trailing: Text(
                      formatTime(list[i].start),
                      style: theme.textTheme.labelMedium,
                    ),
                    onTap: () {
                      handler.seek(list[i].start);
                      Navigator.of(context).pop();
                    },
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// Chapter name and the time left in it.
class ChapterLine extends ConsumerWidget {
  const ChapterLine({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handler = ref.watch(audioHandlerProvider);
    final theme = Theme.of(context);
    final position = ref.watch(positionProvider).value ?? Duration.zero;
    final list = handler.chapters.value;
    final i = chapterIndexAt(list, position);
    if (i < 0) return const SizedBox.shrink();
    final (_, end) = handler.chapterBounds(position);
    return Row(
      children: [
        Expanded(
          child: Text(
            list[i].title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const SizedBox(width: Space.m),
        Text(
          '${formatTime(end - position)} left',
          style: theme.textTheme.labelMedium,
        ),
      ],
    );
  }
}

class _Captioned extends StatelessWidget {
  const _Captioned(this.label, this.child);

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 52,
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        child,
        Text(
          label,
          style: Theme.of(context).textTheme.labelMedium
              ?.copyWith(fontSize: 11),
        ),
      ],
    ),
  );
}

/// The floating card of the 2-in-1 screen.
class PlayerBar extends ConsumerWidget {
  const PlayerBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.twofold;
    final scheme = Theme.of(context).colorScheme;
    final handler = ref.watch(audioHandlerProvider);
    return Material(
      color: scheme.surfaceContainerHigh,
      elevation: 3,
      shadowColor: scheme.shadow.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(Space.cardRadius),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.l, Space.m),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ChapterLine(),
            Scrubber(onSurface: scheme.surfaceContainerHigh),
            const SizedBox(height: Space.xs),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const _Captioned(
                  'Speed',
                  SizedBox(height: 36, child: SpeedButton()),
                ),
                const SkipButton(forward: false, size: 52),
                const PlayButton(size: 60),
                const SkipButton(forward: true, size: 52),
                _Captioned(
                  'Sleep',
                  SizedBox(
                    height: 36,
                    child: ValueListenableBuilder(
                      valueListenable: handler.sleep,
                      builder: (context, timer, _) => IconButton(
                        tooltip: 'Sleep timer',
                        padding: EdgeInsets.zero,
                        onPressed: () => showSleepSheet(context),
                        icon: Icon(
                          Icons.bedtime_outlined,
                          color: timer == null ? c.text : c.accent,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
