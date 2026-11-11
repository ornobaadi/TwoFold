import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';
import 'package:uuid/uuid.dart';

import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../audio/downloads.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../../find/librivox.dart';
import '../../find/web.dart';
import '../find/providers.dart';
import '../library/providers.dart';

/// "13 h 7 min", "42 min".
String formatLength(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  if (h == 0) return '$m min';
  return m == 0 ? '$h h' : '$h h $m min';
}

/// The Gutenberg number of a book that came from Gutenberg through Find.
Future<String?> gutenbergIdOf(WidgetRef ref, Book book) async {
  final d = await ref.read(bookRepoProvider).detailsFor(book.id);
  if (d == null || d.source != 'Project Gutenberg') return null;
  return d.sourceId;
}

/// Gives [book] the recording [r]: every part online, saved for offline in
/// the background when [save]. Replaces audio the book had. Never plays.
Future<void> attachRecording(
  WidgetRef ref,
  Book book,
  LibrivoxBook r, {
  required bool save,
}) async {
  final repo = ref.read(bookRepoProvider);
  final downloads = ref.read(downloadsProvider);
  // A previous recording's saved files go first.
  await downloads.forget(book.id).catchError((_) {});
  const uuid = Uuid();
  await repo.setAudiobook(
    Audiobook(
      bookId: book.id,
      source: 'librivox',
      sourceId: r.id,
      title: r.title,
      reader: r.readerLine,
      pageUrl: r.pageUrl?.toString(),
      totalMs: r.total.inMilliseconds,
      parts: r.parts.length,
      addedAt: DateTime.now().millisecondsSinceEpoch,
    ),
    [
      for (final (i, part) in r.parts.indexed)
        AudioTrack(
          id: uuid.v4(),
          bookId: book.id,
          filePath: part.url.toString(),
          remoteUrl: part.url.toString(),
          position: i,
          durationMs: part.duration.inMilliseconds,
          title: part.title,
        ),
    ],
  );
  if (save) {
    downloads.wifiOnly = ref.read(settingsProvider).wifiOnlyDownloads;
    unawaited(downloads.saveAll(book.id).catchError((_) {}));
  }
  await ref.read(audioHandlerProvider).loadBook(book, reload: true);
  ref.invalidate(libraryProvider);
}

/// Picks a free LibriVox recording for [book]. Returns true when one was added.
Future<bool> showAudiobookSheet(BuildContext context, Book book) async =>
    await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => AudiobookSheet(book: book),
    ) ==
    true;

class AudiobookSheet extends ConsumerStatefulWidget {
  const AudiobookSheet({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<AudiobookSheet> createState() => _AudiobookSheetState();
}

class _AudiobookSheetState extends ConsumerState<AudiobookSheet> {
  late Future<(List<LibrivoxBook>, String?)> _found;
  int _chosen = 0;
  bool _save = true;
  bool _adding = false;
  String? _error;

  // A short sample through its own player; the book's player is paused.
  AudioPlayer? _preview;
  String? _previewing;

  @override
  void initState() {
    super.initState();
    _look();
  }

  @override
  void dispose() {
    _preview?.dispose();
    super.dispose();
  }

  void _look() {
    setState(() {
      _error = null;
      _found = () async {
        final id = await gutenbergIdOf(ref, widget.book);
        final list = await ref
            .read(findServiceProvider)
            .librivox
            .find(widget.book.title, author: widget.book.author, gutenbergId: id);
        return (list, id);
      }();
    });
  }

  Future<void> _togglePreview(LibrivoxBook r) async {
    if (_previewing == r.id) {
      await _preview?.stop();
      setState(() => _previewing = null);
      return;
    }
    await ref.read(audioHandlerProvider).pause();
    final player = _preview ??= AudioPlayer();
    setState(() => _previewing = r.id);
    try {
      await player.setAudioSource(
        AudioSource.uri(r.parts.first.url, headers: const {'User-Agent': userAgent}),
      );
      unawaited(player.play());
    } catch (_) {
      if (mounted) {
        setState(() {
          _previewing = null;
          _error = 'The sample could not be played. Check your connection.';
        });
      }
    }
  }

  Future<void> _add(LibrivoxBook r) async {
    setState(() {
      _adding = true;
      _error = null;
    });
    await _preview?.stop();
    try {
      await attachRecording(ref, widget.book, r, save: _save);
      if (mounted) Navigator.of(context).pop(true);
    } catch (_) {
      if (mounted) {
        setState(() {
          _adding = false;
          _error = 'The audiobook could not be added. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final wifiOnly = ref.watch(settingsProvider.select((x) => x.wifiOnlyDownloads));
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => FutureBuilder<(List<LibrivoxBook>, String?)>(
        future: _found,
        builder: (context, snap) {
          final list = snap.data?.$1;
          final gid = snap.data?.$2;
          final chosen = list == null || list.isEmpty
              ? null
              : list[_chosen.clamp(0, list.length - 1)];
          return Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.l),
                  children: [
                    Text('Free audiobook', style: theme.textTheme.titleLarge),
                    const SizedBox(height: Space.xs),
                    Text(
                      'Read by LibriVox volunteers and free to keep. '
                      'Plays straight away and saves itself for offline.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.l),
                    if (snap.hasError)
                      _Note(
                        snap.error is WebError
                            ? (snap.error! as WebError).message
                            : 'LibriVox could not be reached.',
                        action: 'Try again',
                        onAction: _look,
                      )
                    else if (list == null)
                      const Padding(
                        padding: EdgeInsets.all(Space.xl),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    else if (list.isEmpty)
                      const _Note(
                        'LibriVox has no recording of this title yet. '
                        'You can still add your own audio files in Edit book.',
                      )
                    else ...[
                      if (gid == null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: Space.s),
                          child: Text(
                            'Matched by title and author. Check the reader follows your edition.',
                            style: theme.textTheme.bodySmall,
                          ),
                        ),
                      for (final (i, r) in list.indexed)
                        _RecordingRow(
                          recording: r,
                          selected: i == _chosen,
                          matches: gid != null && r.gutenbergId == gid,
                          previewing: _previewing == r.id,
                          onTap: () => setState(() => _chosen = i),
                          onPreview: () => _togglePreview(r),
                        ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: Space.s),
                      Text(
                        _error!,
                        style: theme.textTheme.bodySmall?.copyWith(color: s.error),
                      ),
                    ],
                  ],
                ),
              ),
              if (chosen != null)
                Material(
                  color: s.surface,
                  child: SafeArea(
                    top: false,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Divider(height: 1),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: Space.l),
                          title: const Text('Save for offline'),
                          subtitle: Text(
                            '${formatSize(chosen.bytes)}'
                            '${wifiOnly ? ', on Wi-Fi only' : ''}. You can listen while it saves.',
                          ),
                          value: _save,
                          onChanged: (v) => setState(() => _save = v),
                        ),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                          child: SizedBox(
                            width: double.infinity,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                backgroundColor: s.onSurface,
                                foregroundColor: s.surface,
                              ),
                              onPressed: _adding ? null : () => _add(chosen),
                              icon: _adding
                                  ? SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: s.surface,
                                      ),
                                    )
                                  : const Icon(Icons.headphones_rounded),
                              label: Text(_adding ? 'Adding…' : 'Add audiobook'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _RecordingRow extends StatelessWidget {
  const _RecordingRow({
    required this.recording,
    required this.selected,
    required this.matches,
    required this.previewing,
    required this.onTap,
    required this.onPreview,
  });

  final LibrivoxBook recording;
  final bool selected;
  final bool matches;
  final bool previewing;
  final VoidCallback onTap;
  final VoidCallback onPreview;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final r = recording;
    return Padding(
      padding: const EdgeInsets.only(bottom: Space.s),
      child: Material(
        color: Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(
            color: selected ? s.onSurface : s.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(Space.m, Space.m, Space.xs, Space.m),
            child: Row(
              children: [
                Icon(
                  selected ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                  color: selected ? s.onSurface : s.onSurfaceVariant,
                ),
                const SizedBox(width: Space.m),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Read by ${r.readerLine}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        [
                          formatLength(r.total),
                          '${r.parts.length} parts',
                          formatSize(r.bytes),
                          if (r.language.isNotEmpty && r.language != 'English') r.language,
                        ].join(' · '),
                        style: theme.textTheme.bodySmall,
                      ),
                      if (matches || r.dramatic)
                        Padding(
                          padding: const EdgeInsets.only(top: Space.xs),
                          child: Text(
                            matches ? 'Matches this edition' : 'Dramatic reading, several voices',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: matches ? s.primary : s.onSurfaceVariant,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  tooltip: previewing ? 'Stop sample' : 'Play a sample',
                  onPressed: onPreview,
                  icon: Icon(previewing ? Icons.stop_rounded : Icons.play_arrow_rounded),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note(this.text, {this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: Space.l),
    child: Column(
      children: [
        Text(text, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        if (action != null) TextButton(onPressed: onAction, child: Text(action!)),
      ],
    ),
  );
}
