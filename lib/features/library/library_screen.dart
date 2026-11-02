import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/bubbly.dart';
import '../../app/format.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import 'book_card.dart';
import 'providers.dart';

/// Filters by title or author, then sorts. Recent keeps the order it was given.
List<LibraryEntry> arrangeLibrary(
  List<LibraryEntry> entries,
  String query,
  LibrarySort sort,
) {
  final q = query.trim().toLowerCase();
  final out = [
    for (final e in entries)
      if (q.isEmpty ||
          e.book.title.toLowerCase().contains(q) ||
          (e.book.author ?? '').toLowerCase().contains(q))
        e,
  ];
  int byTitle(LibraryEntry a, LibraryEntry b) =>
      a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase());
  switch (sort) {
    case LibrarySort.recent:
      break;
    case LibrarySort.title:
      out.sort(byTitle);
    case LibrarySort.author:
      out.sort((a, b) {
        final byAuthor = (a.book.author ?? '\u{10FFFF}')
            .toLowerCase()
            .compareTo((b.book.author ?? '\u{10FFFF}').toLowerCase());
        return byAuthor != 0 ? byAuthor : byTitle(a, b);
      });
  }
  return out;
}

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key, this.resumeBookId});

  /// Book that was open when the app last closed; reopened right away.
  final String? resumeBookId;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';

  @override
  void initState() {
    super.initState();
    final id = widget.resumeBookId;
    if (id != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        final book = await ref.read(bookRepoProvider).getBook(id);
        if (book != null && mounted) _open(book, instant: true);
      });
    }
  }

  Future<void> _open(Book book, {bool instant = false}) async {
    await openReader(context, book, instant: instant);
    if (mounted) ref.invalidate(libraryProvider);
  }

  Future<void> _add() async {
    final book = await openNewBook(context);
    if (!mounted) return;
    ref.invalidate(libraryProvider);
    if (book != null) _open(book);
  }

  void _showActions(LibraryEntry entry) {
    showModalBottomSheet<void>(
      context: context,
      builder: (sheet) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                Space.xl,
                0,
                Space.xl,
                Space.s,
              ),
              child: Text(
                entry.book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Edit book'),
              subtitle: const Text('Title, author, cover and audio'),
              onTap: () => _edit(sheet, entry.book),
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              iconColor: Theme.of(context).colorScheme.error,
              textColor: Theme.of(context).colorScheme.error,
              leading: const Icon(Icons.delete_outline_rounded),
              title: const Text('Remove from library'),
              onTap: () {
                Navigator.of(sheet).pop();
                _confirmRemove(entry.book);
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _edit(BuildContext sheet, Book book) async {
    Navigator.of(sheet).pop();
    await openEditBook(context, book);
    if (mounted) ref.invalidate(libraryProvider);
  }

  Future<void> _confirmRemove(Book book) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (d) => AlertDialog(
        title: Text('Remove "${book.title}"?'),
        content: const Text(
          'Your place and saved spots in this book are deleted. '
          'Your original files stay on your phone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(d).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(d).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (yes != true) return;
    final handler = ref.read(audioHandlerProvider);
    if (handler.bookId == book.id) await handler.unload();
    await ref.read(importerProvider).removeBook(book.id);
    if (mounted) ref.invalidate(libraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider);
    final entries = library.value ?? const <LibraryEntry>[];
    final sort = ref.watch(settingsProvider.select((s) => s.sort));
    final shown = arrangeLibrary(entries, _query, sort);
    LibraryEntry? recent;
    for (final e in entries) {
      if (e.book.lastOpened != null) {
        recent = e;
        break;
      }
    }
    final filtering = _query.trim().isNotEmpty;
    final width = MediaQuery.sizeOf(context).width - Space.l * 2;
    final columns = (width / 105).floor().clamp(2, 8);
    final itemWidth = (width - Space.l * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Scaffold(
      floatingActionButton: Bubbly(
        child: FloatingActionButton.extended(
          onPressed: _add,
          icon: const Icon(Icons.add_rounded),
          label: const Text('Add book'),
        ),
      ),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                Space.l,
                Space.l,
                Space.xs,
                Space.m,
              ),
              sliver: SliverToBoxAdapter(
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'TwoFold',
                        style: theme.textTheme.displaySmall,
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
            ),
            if (library.hasError && entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: Center(
                  child: Text(
                    'Could not open your library.',
                    style: theme.textTheme.bodyLarge,
                  ),
                ),
              )
            else if (library.hasValue && entries.isEmpty)
              SliverFillRemaining(
                hasScrollBody: false,
                child: _Empty(onImport: _add),
              )
            else ...[
              if (recent != null && !filtering)
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    0,
                    Space.l,
                    Space.l,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _ContinueCard(
                      entry: recent,
                      onOpen: () => _open(recent!.book),
                    ),
                  ),
                ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(
                  Space.l,
                  0,
                  Space.xs,
                  Space.l,
                ),
                sliver: SliverToBoxAdapter(
                  child: Row(
                    children: [
                      Expanded(
                        child: SearchBar(
                          hintText: 'Search your books',
                          elevation: const WidgetStatePropertyAll(0),
                          constraints: const BoxConstraints(minHeight: 52),
                          leading: const Padding(
                            padding: EdgeInsets.only(left: Space.s),
                            child: Icon(Icons.search_rounded),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                      ),
                      PopupMenuButton<LibrarySort>(
                        tooltip: 'Sort',
                        icon: const Icon(Icons.sort_rounded),
                        initialValue: sort,
                        onSelected: (v) => ref
                            .read(settingsProvider.notifier)
                            .change(
                              ref.read(settingsProvider).copyWith(sort: v),
                            ),
                        itemBuilder: (_) => const [
                          PopupMenuItem(
                            value: LibrarySort.recent,
                            child: Text('Recently opened'),
                          ),
                          PopupMenuItem(
                            value: LibrarySort.title,
                            child: Text('Title'),
                          ),
                          PopupMenuItem(
                            value: LibrarySort.author,
                            child: Text('Author'),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              if (filtering && shown.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(Space.xl),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      'No books match "${_query.trim()}".',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
                    ),
                  ),
                ),
              SliverPadding(
                // Leaves the last row clear of the add button.
                padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, 96),
                sliver: SliverGrid.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: columns,
                    crossAxisSpacing: Space.l,
                    mainAxisSpacing: Space.xl,
                    mainAxisExtent: itemWidth * 1.5 + 84 * textScale,
                  ),
                  itemCount: shown.length,
                  itemBuilder: (_, i) => BookCard(
                    entry: shown[i],
                    onTap: () => _open(shown[i].book),
                    onOptions: () => _showActions(shown[i]),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(Space.xl, 0, Space.xl, 96),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(32),
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 44,
              color: theme.colorScheme.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: Space.xl),
          Text(
            'Read it. Hear it.\nNever lose your place.',
            textAlign: TextAlign.center,
            style: theme.textTheme.headlineMedium,
          ),
          const SizedBox(height: Space.m),
          Text(
            'Add an EPUB or PDF, then its audiobook.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge,
          ),
        ],
      ),
    );
  }
}

/// The one thing most people came here to do: carry on.
class _ContinueCard extends ConsumerWidget {
  const _ContinueCard({required this.entry, required this.onOpen});

  final LibraryEntry entry;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final handler = ref.watch(audioHandlerProvider);
    final loaded = handler.bookId == entry.book.id;
    final playing =
        loaded && (ref.watch(playbackStateProvider).value?.playing ?? false);
    final position = loaded
        ? (ref.watch(positionProvider).value ?? entry.audioPosition)
        : entry.audioPosition;
    final percent = entry.progress?.readPercent ?? 0;

    Future<void> toggle() async {
      if (playing) return handler.pause();
      await handler.loadBook(entry.book);
      await handler.play();
    }

    return Bubbly(
      squish: 0.97,
      child: Material(
        color: s.primaryContainer,
        borderRadius: BorderRadius.circular(Space.cardRadius),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: const EdgeInsets.all(Space.l),
            child: Row(
              children: [
                SizedBox(
                  width: 72,
                  child: BookCover(book: entry.book, titleSize: 8.5),
                ),
                const SizedBox(width: Space.l),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Continue',
                        style: theme.textTheme.labelLarge?.copyWith(
                          color: s.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        entry.book.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleLarge?.copyWith(
                          color: s.onPrimaryContainer,
                        ),
                      ),
                      const SizedBox(height: Space.s),
                      WavyProgress(
                        value: percent,
                        color: s.primary,
                        track: s.onPrimaryContainer.withValues(alpha: 0.15),
                      ),
                      const SizedBox(height: Space.xs),
                      Text(
                        [
                          '${(percent * 100).round()}% read',
                          if (entry.hasAudio) formatTime(position),
                        ].join(' · '),
                        style: theme.textTheme.labelMedium?.copyWith(
                          color: s.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
                if (entry.hasAudio) ...[
                  const SizedBox(width: Space.s),
                  Semantics(
                    button: true,
                    label: playing ? 'Pause' : 'Play',
                    child: Bubbly(
                      squish: 0.84,
                      child: GestureDetector(
                        onTap: toggle,
                        child: AnimatedContainer(
                          duration: springDuration,
                          curve: springCurve,
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: s.primary,
                            borderRadius: BorderRadius.circular(
                              playing ? 20 : 32,
                            ),
                          ),
                          child: Icon(
                            playing
                                ? Icons.pause_rounded
                                : Icons.play_arrow_rounded,
                            size: 34,
                            color: s.onPrimary,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
