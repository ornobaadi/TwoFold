import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/press.dart';
import '../../app/format.dart';
import '../../app/router.dart';
import '../../app/settings.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import 'book_card.dart';
import 'cover_picker.dart';
import '../listen/audiobook_sheet.dart';
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
  const LibraryScreen({super.key, this.resumeBookId, this.onFind});

  /// Book that was open when the app last closed; reopened right away.
  final String? resumeBookId;

  /// Shows the Find tab; without it, Find opens as its own screen.
  final VoidCallback? onFind;

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

/// Which books the shelf shows.
enum ShelfFilter {
  all('All'),
  audio('With audio'),
  downloaded('Downloaded');

  const ShelfFilter(this.label);
  final String label;

  bool keeps(LibraryEntry e) => switch (this) {
    all => true,
    audio => e.hasAudio,
    downloaded => e.downloaded,
  };
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  String _query = '';
  ShelfFilter _filter = ShelfFilter.all;

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

  Future<void> _find() async {
    final tab = widget.onFind;
    if (tab != null) return tab();
    await openFind(context);
    if (mounted) ref.invalidate(libraryProvider);
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
              leading: const Icon(Icons.info_outline_rounded),
              title: const Text('About this book'),
              subtitle: const Text('Details, rating and where it came from'),
              onTap: () {
                Navigator.of(sheet).pop();
                openBookDetails(context, entry.book);
              },
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
              leading: const Icon(Icons.headphones_outlined),
              title: Text(entry.hasAudio ? 'Change audiobook' : 'Find a free audiobook'),
              subtitle: const Text('Recordings from LibriVox volunteers'),
              onTap: () {
                Navigator.of(sheet).pop();
                showAudiobookSheet(context, entry.book);
              },
            ),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: Space.xl),
              leading: const Icon(Icons.image_outlined),
              title: const Text('Change cover'),
              subtitle: const Text('Pick from Open Library or your phone'),
              onTap: () => _changeCover(sheet, entry.book),
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

  Future<void> _changeCover(BuildContext sheet, Book book) async {
    Navigator.of(sheet).pop();
    final path = await showCoverPicker(context, book: book);
    if (path == null || !mounted) return;
    await ref.read(bookRepoProvider).setCover(book.id, path);
    ref.invalidate(libraryProvider);
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
    // Saved free audiobook files live outside the book folder.
    await ref.read(downloadsProvider).forget(book.id).catchError((_) {});
    await ref.read(importerProvider).removeBook(book.id);
    if (mounted) ref.invalidate(libraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = ref.watch(libraryProvider);
    final entries = library.value ?? const <LibraryEntry>[];
    final sort = ref.watch(settingsProvider.select((s) => s.sort));
    final shown =
        arrangeLibrary(entries, _query, sort).where(_filter.keeps).toList();
    LibraryEntry? recent;
    for (final e in entries) {
      if (e.book.lastOpened != null) {
        recent = e;
        break;
      }
    }
    // With nothing opened yet, the newest book is offered to start.
    final featured = recent ?? (entries.isEmpty ? null : entries.first);
    final filtering = _query.trim().isNotEmpty;
    final width = MediaQuery.sizeOf(context).width - Space.l * 2;
    // Three across reads best on phones; tablets get more.
    final columns = width < 600 ? 3 : (width / 140).floor().clamp(4, 8);
    final itemWidth = (width - Space.l * (columns - 1)) / columns;
    final textScale = MediaQuery.textScalerOf(context).scale(1);

    return Scaffold(
      floatingActionButton: Pressable(
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
                        style: theme.textTheme.displaySmall?.copyWith(
                          fontSize: 22,
                        ),
                      ),
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
                child: _Empty(onImport: _add, onFind: _find),
              )
            else ...[
              if (featured != null && !filtering) ...[
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    Space.s,
                    Space.l,
                    Space.xl,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: _Featured(
                      entry: featured,
                      started: recent != null,
                      onOpen: () => _open(featured.book),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(
                    Space.l,
                    0,
                    Space.l,
                    Space.m,
                  ),
                  sliver: SliverToBoxAdapter(
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            'On your shelf',
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        Text(
                          entries.length == 1
                              ? '1 book'
                              : '${entries.length} books',
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
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
                          constraints: const BoxConstraints(minHeight: 44),
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
              if (entries.any((e) => e.hasAudio))
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(Space.l, 0, Space.l, Space.m),
                  sliver: SliverToBoxAdapter(
                    child: Wrap(
                      spacing: Space.s,
                      children: [
                        for (final f in ShelfFilter.values)
                          ChoiceChip(
                            label: Text(
                              '${f.label} ${entries.where(f.keeps).length}',
                            ),
                            selected: _filter == f,
                            onSelected: (_) => setState(() => _filter = f),
                          ),
                      ],
                    ),
                  ),
                ),
              if (!filtering && shown.isEmpty)
                SliverPadding(
                  padding: const EdgeInsets.all(Space.xl),
                  sliver: SliverToBoxAdapter(
                    child: Text(
                      _filter == ShelfFilter.downloaded
                          ? 'No audiobooks are fully on this phone yet. '
                              'Download one from its About page.'
                          : 'No books here yet.',
                      textAlign: TextAlign.center,
                      style: theme.textTheme.bodyLarge,
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
                    mainAxisSpacing: Space.l,
                    mainAxisExtent: itemWidth * 1.5 + 78 * textScale,
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
  const _Empty({required this.onImport, required this.onFind});

  final VoidCallback onImport;
  final VoidCallback onFind;

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
              color: theme.colorScheme.surfaceContainer,
              borderRadius: BorderRadius.circular(Space.cardRadius),
            ),
            child: Icon(
              Icons.auto_stories_outlined,
              size: 44,
              color: theme.colorScheme.onSurfaceVariant,
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
          const SizedBox(height: Space.l),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(minimumSize: const Size(0, 48)),
            onPressed: onFind,
            icon: const Icon(Icons.travel_explore_rounded),
            label: const Text('Find free books'),
          ),
        ],
      ),
    );
  }
}

/// The hero label: carry on at this time of day, or start something new.
String readLabel(DateTime now, {required bool started}) {
  if (!started) return 'Start here';
  final h = now.hour;
  if (h >= 5 && h < 12) return "This morning's read";
  if (h >= 12 && h < 18) return "This afternoon's read";
  return "Tonight's read";
}

/// The book to carry on with (or to start) as the hero of the home screen.
/// Colours come from the theme's roles, so it follows the chosen palette and
/// background.
class _Featured extends ConsumerWidget {
  const _Featured({
    required this.entry,
    required this.started,
    required this.onOpen,
  });

  final LibraryEntry entry;
  final bool started;
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
    final total = entry.audioTotal;

    Future<void> toggle() async {
      if (playing) return handler.pause();
      await handler.loadBook(entry.book);
      await handler.play();
    }


    final muted = theme.textTheme.bodyMedium?.copyWith(color: s.onSurfaceVariant);
    final audioLine = !entry.hasAudio || total <= Duration.zero
        ? null
        : started && position > Duration.zero
            ? '${formatTime(total - position)} of audio left'
            : '${formatTime(total)} of audio';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          readLabel(DateTime.now(), started: started).toUpperCase(),
          style: theme.textTheme.labelLarge?.copyWith(
            color: s.primary,
            letterSpacing: 1.4,
          ),
        ),
        const SizedBox(height: Space.m),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Semantics(
              button: true,
              label: 'Open ${entry.book.title}',
              child: Pressable(
                child: GestureDetector(
                  onTap: onOpen,
                  onLongPress: () => openBookDetails(context, entry.book),
                  child: SizedBox(
                    width: 132,
                    child: BookCover(book: entry.book, titleSize: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: Space.l),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: Space.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      entry.book.title,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontFamily: serifFont,
                        fontWeight: FontWeight.w700,
                        fontSize: 22,
                        height: 1.15,
                      ),
                    ),
                    if (entry.book.author != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        entry.book.author!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: muted,
                      ),
                    ],
                    const SizedBox(height: Space.m),
                    Container(width: 28, height: 1.5, color: s.outlineVariant),
                    const SizedBox(height: Space.m),
                    _Fact(
                      icon: Icons.menu_book_outlined,
                      text: started ? '${(percent * 100).round()}% read' : 'Not opened yet',
                    ),
                    if (audioLine != null) ...[
                      const SizedBox(height: Space.xs),
                      _Fact(icon: Icons.headphones_rounded, text: audioLine),
                    ],
                    if (started) ...[
                      const SizedBox(height: Space.s),
                      ProgressLine(
                        value: percent,
                        color: s.primary,
                        track: s.onSurface.withValues(alpha: 0.12),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: Space.l),
        Row(
          children: [
            Expanded(
              child: Pressable(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    backgroundColor: s.onSurface,
                    foregroundColor: s.surface,
                  ),
                  onPressed: onOpen,
                  icon: const Icon(Icons.menu_book_rounded),
                  label: Text(started ? 'Keep reading' : 'Start reading'),
                ),
              ),
            ),
            if (entry.hasAudio) ...[
              const SizedBox(width: Space.m),
              Expanded(
                child: Pressable(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      minimumSize: const Size(0, 44),
                      backgroundColor: s.primary,
                      foregroundColor: s.onPrimary,
                    ),
                    onPressed: toggle,
                    icon: Icon(
                      playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                    ),
                    label: Text(playing ? 'Pause' : 'Listen'),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

/// One line under the featured book: an icon and a short fact.
class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        Icon(icon, size: 16, color: muted),
        const SizedBox(width: Space.s),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium?.copyWith(color: muted),
          ),
        ),
      ],
    );
  }
}
