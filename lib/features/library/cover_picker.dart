import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/theme.dart';
import '../../data/models.dart';
import '../../find/cover_source.dart';
import '../../find/web.dart';
import '../../import/device_files.dart';
import '../find/providers.dart';
import 'book_card.dart';
import 'providers.dart';

/// Lets the user pick a cover from Open Library's editions of the book, or a
/// picture on the phone. Returns the saved cover file, or null if nothing
/// was chosen. The caller decides when to store it on the book.
Future<String?> showCoverPicker(
  BuildContext context, {
  required Book book,
}) => showModalBottomSheet<String>(
  context: context,
  isScrollControlled: true,
  useSafeArea: true,
  builder: (_) => CoverPicker(book: book),
);

class CoverPicker extends ConsumerStatefulWidget {
  const CoverPicker({super.key, required this.book});

  final Book book;

  @override
  ConsumerState<CoverPicker> createState() => _CoverPickerState();
}

class _CoverPickerState extends ConsumerState<CoverPicker> {
  late Future<List<CoverCandidate>> _found;
  int? _saving;
  String? _error;

  @override
  void initState() {
    super.initState();
    _search();
  }

  void _search() {
    final b = widget.book;
    setState(() {
      _error = null;
      _found = ref.read(findServiceProvider).covers.search(b.title, b.author);
    });
  }

  Future<void> _choose(CoverCandidate c) async {
    setState(() {
      _saving = c.id;
      _error = null;
    });
    try {
      final covers = ref.read(findServiceProvider).covers;
      final bytes = await covers.image(c.full) ?? await covers.image(c.thumb);
      if (bytes == null) throw const WebError('That cover could not be loaded.');
      final path = await ref
          .read(importerProvider)
          .saveCoverBytes(widget.book.id, bytes);
      if (mounted) Navigator.of(context).pop(path);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = null;
          _error = e is WebError ? e.message : 'That cover could not be saved.';
        });
      }
    }
  }

  Future<void> _fromPhone() async {
    final file = await DeviceFiles.pickImage();
    if (file == null) return;
    try {
      final path = await ref
          .read(importerProvider)
          .saveCover(widget.book.id, file);
      if (mounted) Navigator.of(context).pop(path);
    } catch (_) {
      if (mounted) setState(() => _error = 'That image could not be used.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = context.twofold;
    return DraggableScrollableSheet(
      expand: false,
      initialChildSize: 0.9,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      builder: (context, scroll) => CustomScrollView(
        controller: scroll,
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
            sliver: SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Choose a cover', style: theme.textTheme.titleLarge),
                  const SizedBox(height: Space.xs),
                  Text(
                    'Covers of other editions of this book, from Open Library.',
                    style: theme.textTheme.bodySmall,
                  ),
                  const SizedBox(height: Space.m),
                  Row(
                    children: [
                      SizedBox(
                        width: 48,
                        child: ExcludeSemantics(
                          child: BookCover(book: widget.book, titleSize: 6),
                        ),
                      ),
                      const SizedBox(width: Space.m),
                      Expanded(
                        child: Text(
                          widget.book.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _saving == null ? _fromPhone : null,
                        icon: const Icon(Icons.photo_outlined, size: 18),
                        label: const Text('From phone'),
                      ),
                    ],
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: Space.s),
                    Text(
                      _error!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.error,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          FutureBuilder<List<CoverCandidate>>(
            future: _found,
            builder: (context, snap) {
              if (snap.hasError) {
                final e = snap.error;
                return _Note(
                  text: e is WebError
                      ? e.message
                      : 'Covers could not be loaded.',
                  action: 'Try again',
                  onAction: _search,
                );
              }
              final list = snap.data;
              if (list == null) return const _Grid(count: 9);
              if (list.isEmpty) {
                return const _Note(
                  text:
                      'Open Library has no covers for this title. You can use a picture from your phone.',
                );
              }
              return _Grid(
                count: list.length,
                item: (i) => _Tile(
                  candidate: list[i],
                  saving: _saving == list[i].id,
                  enabled: _saving == null,
                  onTap: () => _choose(list[i]),
                ),
              );
            },
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.all(Space.l),
              child: Text(
                'Covers belong to their publishers and are shown by Open Library.',
                style: theme.textTheme.bodySmall?.copyWith(color: c.muted),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Grid extends StatelessWidget {
  const _Grid({required this.count, this.item});

  final int count;

  /// Null while loading: plain tiles stand in.
  final Widget Function(int)? item;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: Space.l),
      sliver: SliverGrid.builder(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 3,
          crossAxisSpacing: Space.m,
          mainAxisSpacing: Space.m,
          childAspectRatio: 2 / 3.4,
        ),
        itemCount: count,
        itemBuilder: (_, i) =>
            item?.call(i) ??
            DecoratedBox(
              decoration: BoxDecoration(
                color: s.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Space.s),
              ),
            ),
      ),
    );
  }
}

class _Tile extends ConsumerWidget {
  const _Tile({
    required this.candidate,
    required this.saving,
    required this.enabled,
    required this.onTap,
  });

  final CoverCandidate candidate;
  final bool saving;
  final bool enabled;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final covers = ref.watch(findServiceProvider).covers;
    return Semantics(
      button: true,
      label: 'Use this cover${candidate.label == null ? '' : ', ${candidate.label}'}',
      excludeSemantics: true,
      child: GestureDetector(
        onTap: enabled ? onTap : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Space.s),
                child: ColoredBox(
                  color: s.surfaceContainerHigh,
                  child: FutureBuilder<Uint8List?>(
                    future: covers.image(candidate.thumb),
                    builder: (context, snap) {
                      final bytes = snap.data;
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          if (bytes != null)
                            Image.memory(bytes, fit: BoxFit.cover, gaplessPlayback: true)
                          else if (snap.connectionState == ConnectionState.done)
                            Icon(Icons.image_not_supported_outlined, color: s.onSurfaceVariant),
                          if (saving)
                            ColoredBox(
                              color: s.surface.withValues(alpha: 0.6),
                              child: const Center(
                                child: SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Text(
              candidate.label ?? '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelSmall,
            ),
          ],
        ),
      ),
    );
  }
}

class _Note extends StatelessWidget {
  const _Note({required this.text, this.action, this.onAction});

  final String text;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
    child: Padding(
      padding: const EdgeInsets.all(Space.l),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (action != null)
            TextButton(onPressed: onAction, child: Text(action!)),
        ],
      ),
    ),
  );
}
