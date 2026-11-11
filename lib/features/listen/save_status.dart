import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/press.dart';
import '../../app/theme.dart';
import '../../audio/downloads.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';

/// Who reads a free recording, and how much of it is saved for offline, with
/// Save, Pause and Remove. Shows nothing for a book without one.
class SaveStatus extends ConsumerStatefulWidget {
  const SaveStatus({super.key, required this.bookId, this.compact = false});

  final String bookId;

  /// One line, for the Listen screen.
  final bool compact;

  @override
  ConsumerState<SaveStatus> createState() => _SaveStatusState();
}

class _SaveStatusState extends ConsumerState<SaveStatus> {
  Audiobook? _book;
  SaveProgress _p = SaveProgress.none;
  Timer? _tick;
  late final AudiobookDownloads _downloads;

  @override
  void initState() {
    super.initState();
    _downloads = ref.read(downloadsProvider);
    _downloads.addListener(_read);
    _load();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _downloads.removeListener(_read);
    super.dispose();
  }

  Future<void> _load() async {
    final b = await ref.read(bookRepoProvider).audiobookFor(widget.bookId);
    if (!mounted) return;
    setState(() => _book = b);
    await _downloads.refresh().catchError((_) {});
    await _read();
  }

  Future<void> _read() async {
    final p = await _downloads.progress(widget.bookId);
    if (!mounted) return;
    setState(() => _p = p);
    // Android reports progress only when asked: ask every 2 s while saving.
    if (p.saving && _tick == null) {
      _tick = Timer.periodic(
        const Duration(seconds: 2),
        (_) => _downloads.refresh().catchError((_) {}),
      );
    } else if (!p.saving) {
      _tick?.cancel();
      _tick = null;
    }
  }

  Future<void> _removeSaved() async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: const Text('Remove saved audio?'),
        content: Text(
          'Frees ${formatSize(_p.bytes)}. The audiobook stays and plays '
          'online, and you can save it again.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(d).pop(false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.of(d).pop(true), child: const Text('Remove')),
        ],
      ),
    );
    if (yes == true) await _downloads.removeSaved(widget.bookId);
  }

  @override
  Widget build(BuildContext context) {
    final b = _book;
    if (b == null || _p.parts == 0) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final c = context.twofold;
    final line = _p.complete
        ? 'Saved for offline · ${formatSize(_p.bytes)}'
        : _p.saving
        ? 'Saving for offline: ${_p.saved} of ${_p.parts} parts · '
              '${formatSize(_p.bytes)} of ${formatSize(_p.totalBytes)}'
        : _p.saved == 0
        ? 'Plays online · ${formatSize(_p.totalBytes)} to save'
        : '${_p.saved} of ${_p.parts} parts saved · the rest plays online';
    final action = _p.complete
        ? TextButton(onPressed: _removeSaved, child: const Text('Remove'))
        : _p.saving
        ? TextButton(
            onPressed: () => _downloads.pause(widget.bookId),
            child: const Text('Pause'),
          )
        : TextButton(
            onPressed: () => _downloads.saveAll(widget.bookId),
            child: const Text('Save'),
          );
    final progress = _p.totalBytes == 0 ? 0.0 : (_p.bytes / _p.totalBytes).clamp(0.0, 1.0);

    if (widget.compact) {
      return Row(
        children: [
          Icon(
            _p.complete ? Icons.download_done_rounded : Icons.cloud_download_outlined,
            size: 16,
            color: c.muted,
          ),
          const SizedBox(width: Space.xs),
          Expanded(
            child: Text(
              line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelMedium,
            ),
          ),
          action,
        ],
      );
    }
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.m, Space.s, Space.m),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('AUDIOBOOK', style: theme.textTheme.labelMedium?.copyWith(letterSpacing: 1.2)),
            const SizedBox(height: Space.xs),
            Text(
              'Read by ${b.reader ?? 'LibriVox volunteers'} for LibriVox',
              style: theme.textTheme.titleSmall,
            ),
            Text(
              'Public domain recording · ${b.parts} parts',
              style: theme.textTheme.bodySmall,
            ),
            const SizedBox(height: Space.m),
            if (_p.saving)
              Padding(
                padding: const EdgeInsets.only(right: Space.m, bottom: Space.xs),
                child: ProgressLine(
                  value: progress,
                  color: s.primary,
                  track: s.onSurface.withValues(alpha: 0.12),
                ),
              ),
            Row(
              children: [
                Expanded(child: Text(line, style: theme.textTheme.bodySmall)),
                action,
              ],
            ),
          ],
        ),
      ),
    );
  }
}
