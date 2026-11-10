import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../app/format.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../player/player_bar.dart';
import 'pane.dart';

/// Saved spots: page and audio position, to come back to.
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

  PlaceMark? _deleted;

  Future<void> _delete(PlaceMark m) async {
    await ref.read(bookRepoProvider).deleteMark(m.id);
    _deleted = m;
    await _reload();
  }

  Future<void> _undoDelete() async {
    final m = _deleted;
    if (m == null) return;
    _deleted = null;
    await ref.read(bookRepoProvider).addMark(m);
    await _reload();
  }

  Future<void> _rename(PlaceMark m) async {
    final text = TextEditingController(text: m.note ?? '');
    final note = await showDialog<String>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Name this place'),
        content: TextField(
          controller: text,
          autofocus: true,
          maxLength: 60,
          textCapitalization: TextCapitalization.sentences,
          decoration: const InputDecoration(
            hintText: 'Where the letter arrives',
          ),
          onSubmitted: (v) => Navigator.of(d).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(text.text),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (note == null) return;
    await ref.read(bookRepoProvider).renameMark(m.id, note);
    await _reload();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    final hasAudio = _hasAudio;
    final handler = ref.read(audioHandlerProvider);
    // Old "page and audio match" spots from the removed sync are not places.
    final places = _marks.where((m) => !m.synced).toList();
    final here = [
      widget.pageLabel.isEmpty ? 'This page' : widget.pageLabel,
      if (hasAudio) formatTime(handler.absolutePosition),
    ].join('  ·  ');
    final alreadySaved = places.any((m) => m.location == widget.location);

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
            // Where you are now, and one tap to keep it.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.l),
              child: Card(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.m,
                    Space.m,
                    Space.m,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'You are here',
                              style: theme.textTheme.labelMedium,
                            ),
                            const SizedBox(height: 2),
                            Text(here, style: theme.textTheme.titleMedium),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.colorScheme.onSurface,
                          foregroundColor: theme.colorScheme.surface,
                        ),
                        onPressed: alreadySaved
                            ? null
                            : () => _save(synced: false),
                        icon: Icon(
                          alreadySaved
                              ? Icons.bookmark_added_rounded
                              : Icons.bookmark_add_outlined,
                          size: 18,
                        ),
                        label: Text(alreadySaved ? 'Saved' : 'Save'),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            if (_deleted != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  Space.s,
                  Space.s,
                  0,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Place removed',
                        style: theme.textTheme.bodyMedium,
                      ),
                    ),
                    TextButton(
                      onPressed: _undoDelete,
                      child: const Text('Undo'),
                    ),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.l,
                Space.l,
                Space.xs,
              ),
              child: Text(
                places.isEmpty
                    ? 'Places you save show up here. Each keeps the page'
                          '${hasAudio ? ' and the second of audio' : ''}, '
                          'so you can come back to both.'
                    : hasAudio
                    ? 'Tap a place to go back to its page and audio.'
                    : 'Tap a place to go back to its page.',
                style: theme.textTheme.bodySmall,
              ),
            ),
            for (final m in places)
              ListTile(
                leading: Icon(Icons.bookmark_outline_rounded, color: c.muted),
                title: Text(
                  m.note ?? m.pageLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  [
                    if (m.note != null) m.pageLabel,
                    if (m.audioMs != null)
                      formatTime(Duration(milliseconds: m.audioMs!)),
                    whenSaved(
                      DateTime.fromMillisecondsSinceEpoch(m.createdAt),
                      DateTime.now(),
                    ),
                  ].join('  ·  '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _open(m),
                onLongPress: () => _rename(m),
                trailing: PopupMenuButton<String>(
                  tooltip: 'Options for this place',
                  icon: Icon(Icons.more_vert_rounded, color: c.muted),
                  onSelected: (v) => v == 'name' ? _rename(m) : _delete(m),
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'name',
                      child: Text(m.note == null ? 'Name it' : 'Rename'),
                    ),
                    const PopupMenuItem(value: 'delete', child: Text('Remove')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// "Just now", "12 min ago", "Today 14:05", "Yesterday", "3 Nov".
String whenSaved(DateTime d, DateTime now) {
  final mins = now.difference(d).inMinutes;
  if (mins < 1) return 'Just now';
  if (mins < 60) return '$mins min ago';
  final hh = d.hour.toString().padLeft(2, '0');
  final mm = d.minute.toString().padLeft(2, '0');
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(DateTime(d.year, d.month, d.day)).inDays;
  if (days == 0) return 'Today $hh:$mm';
  if (days == 1) return 'Yesterday';
  const months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final label = '${d.day} ${months[d.month - 1]}';
  return d.year == now.year ? label : '$label ${d.year}';
}
