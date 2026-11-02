import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../audio/sync_map.dart';
import '../../data/models.dart';
import '../player/player_bar.dart';
import 'pane.dart';

/// The estimator for a book, from the spots the user said match.
SyncMap syncMapFor(List<PlaceMark> marks, Duration total) => SyncMap([
  if (total > Duration.zero)
    for (final m in marks)
      if (m.synced && m.audioMs != null)
        SyncPoint(m.percent, m.audioMs! / total.inMilliseconds),
]);

/// Saved spots, and moving the page and the audio to match each other.
class PlacesSheet extends ConsumerStatefulWidget {
  const PlacesSheet({
    super.key,
    required this.book,
    required this.location,
    required this.percent,
    required this.pageLabel,
    required this.actions,
  });

  final Book book;
  final String location;
  final double percent;
  final String pageLabel;
  final ReaderActions? actions;

  @override
  ConsumerState<PlacesSheet> createState() => _PlacesSheetState();
}

class _PlacesSheetState extends ConsumerState<PlacesSheet> {
  List<PlaceMark> _marks = const [];

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final marks = await ref.read(bookRepoProvider).marksFor(widget.book.id);
    if (mounted) setState(() => _marks = marks);
  }

  bool get _hasAudio => ref.read(audioHandlerProvider).bookId == widget.book.id;

  Future<void> _save({required bool synced}) async {
    final handler = ref.read(audioHandlerProvider);
    await ref
        .read(bookRepoProvider)
        .addMark(
          PlaceMark(
            id: const Uuid().v4(),
            bookId: widget.book.id,
            location: widget.location,
            percent: widget.percent,
            pageLabel: widget.pageLabel,
            audioMs: _hasAudio ? handler.absolutePosition.inMilliseconds : null,
            createdAt: DateTime.now().millisecondsSinceEpoch,
            synced: synced,
          ),
        );
    await _reload();
  }

  void _open(PlaceMark m) {
    widget.actions?.goTo(m.location);
    final ms = m.audioMs;
    if (ms != null && _hasAudio) {
      ref.read(audioHandlerProvider).seek(Duration(milliseconds: ms));
    }
    Navigator.of(context).pop();
  }

  void _moveAudioToPage() {
    final handler = ref.read(audioHandlerProvider);
    final total = handler.total;
    final f = syncMapFor(_marks, total).audioAt(widget.percent);
    handler.seek(total * f);
    Navigator.of(context).pop();
  }

  void _movePageToAudio() {
    final handler = ref.read(audioHandlerProvider);
    final total = handler.total;
    if (total <= Duration.zero) return;
    final f = handler.absolutePosition.inMilliseconds / total.inMilliseconds;
    widget.actions?.goToFraction(syncMapFor(_marks, total).bookAt(f));
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final hasAudio = _hasAudio;
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
      ),
      child: SafeArea(
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.only(bottom: Space.l),
          children: [
            const SheetTitle('My places'),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: FilledButton.tonalIcon(
                onPressed: () => _save(synced: false),
                icon: const Icon(Icons.bookmark_add_outlined),
                label: const Text('Save this spot'),
              ),
            ),
            for (final m in _marks)
              ListTile(
                leading: Icon(
                  m.synced
                      ? Icons.link_rounded
                      : Icons.bookmark_outline_rounded,
                  color: c.muted,
                ),
                title: Text(
                  [
                    m.pageLabel,
                    if (m.audioMs != null)
                      formatTime(Duration(milliseconds: m.audioMs!)),
                  ].join('  ·  '),
                ),
                subtitle: Text(
                  _when(m.createdAt),
                  style: theme.textTheme.labelMedium,
                ),
                onTap: () => _open(m),
                trailing: IconButton(
                  tooltip: 'Delete this spot',
                  onPressed: () async {
                    await ref.read(bookRepoProvider).deleteMark(m.id);
                    await _reload();
                  },
                  icon: Icon(Icons.close_rounded, color: c.muted),
                ),
              ),
            if (hasAudio) ...[
              const SizedBox(height: Space.l),
              const SheetTitle('Match page and audio'),
              ListTile(
                leading: const Icon(Icons.headphones_outlined),
                title: const Text('Move the audio to this page'),
                subtitle: const Text('Close, not exact'),
                onTap: _moveAudioToPage,
              ),
              ListTile(
                leading: const Icon(Icons.menu_book_outlined),
                title: const Text('Go to the page the audio is on'),
                subtitle: const Text('Close, not exact'),
                onTap: _movePageToAudio,
              ),
              ListTile(
                leading: const Icon(Icons.link_rounded),
                title: const Text('This page and the audio match right now'),
                subtitle: const Text(
                  'Teaches the app. Do this a few times and the two moves above get much closer.',
                ),
                onTap: () => _save(synced: true),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _when(int ms) {
    final d = DateTime.fromMillisecondsSinceEpoch(ms);
    final hh = d.hour.toString().padLeft(2, '0');
    final mm = d.minute.toString().padLeft(2, '0');
    return '${d.day}/${d.month}/${d.year}  $hh:$mm';
  }
}
