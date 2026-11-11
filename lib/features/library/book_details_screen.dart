import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app/format.dart';
import '../../app/press.dart';
import '../../app/router.dart';
import '../../app/theme.dart';
import '../../audio/player_controller.dart';
import '../../data/models.dart';
import '../../find/book_source.dart';
import '../../find/web.dart';
import '../find/details_parts.dart';
import '../find/keep_details.dart';
import '../find/providers.dart';
import '../listen/audiobook_sheet.dart';
import '../listen/save_status.dart';
import 'book_card.dart';
import 'cover_picker.dart';
import 'providers.dart';

/// Everything known about a book: cover, progress, where it came from, and
/// Open Library's rating, description and subjects. Books from Find arrive
/// with these; for the user's own files they are looked up on request.
class BookDetailsScreen extends ConsumerStatefulWidget {
  const BookDetailsScreen({super.key, required this.bookId});

  final String bookId;

  @override
  ConsumerState<BookDetailsScreen> createState() => _BookDetailsScreenState();
}

class _BookDetailsScreenState extends ConsumerState<BookDetailsScreen> {
  BookDetails? _details;
  bool _loaded = false;
  bool _looking = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final d = await ref.read(bookRepoProvider).detailsFor(widget.bookId);
    if (mounted) {
      setState(() {
        _details = d;
        _loaded = true;
      });
    }
  }

  Future<void> _lookUp(Book book) async {
    setState(() {
      _looking = true;
      _error = null;
    });
    try {
      final info = await ref
          .read(findServiceProvider)
          .info
          .lookUp(
            FoundBook(
              source: 'library',
              id: book.id,
              title: book.title,
              author: book.author,
            ),
          );
      final details = detailsFrom(book.id, info, before: _details);
      await ref.read(bookRepoProvider).saveDetails(details);
      if (!mounted) return;
      setState(() {
        _details = details;
        if (info == null) _error = 'Open Library has nothing on this title.';
      });
    } on WebError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } finally {
      if (mounted) setState(() => _looking = false);
    }
  }

  Future<void> _changeCover(Book book) async {
    final path = await showCoverPicker(context, book: book);
    if (path == null || !mounted) return;
    await ref.read(bookRepoProvider).setCover(book.id, path);
    ref.invalidate(libraryProvider);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final c = context.twofold;
    final entries = ref.watch(libraryProvider).value ?? const <LibraryEntry>[];
    LibraryEntry? entry;
    for (final e in entries) {
      if (e.book.id == widget.bookId) entry = e;
    }
    if (entry == null) {
      return Scaffold(
        appBar: AppBar(),
        body: const Center(child: CircularProgressIndicator()),
      );
    }
    final book = entry.book;
    final d = _details;
    final percent = entry.progress?.readPercent ?? 0;
    final added = DateTime.fromMillisecondsSinceEpoch(book.addedAt);
    final about = d?.description ?? d?.summary;
    final facts = <(String, String)>[
      if (d?.source != null) ('From', d!.source!),
      if (d?.firstYear != null) ('First published', '${d!.firstYear}'),
      if (d?.pages != null) ('Pages', '${d!.pages}'),
      ('Format', book.format.toUpperCase()),
      if (entry.hasAudio) ('Audio', formatTime(entry.audioTotal)),
      ('Added', formatDate(added)),
    ];

    return Scaffold(
      appBar: AppBar(title: const Text('About this book')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Space.l, Space.s, Space.l, Space.xxl),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  Semantics(
                    button: true,
                    label: 'Change cover',
                    child: Pressable(
                      child: GestureDetector(
                        onTap: () => _changeCover(book),
                        child: SizedBox(
                          width: 112,
                          child: ExcludeSemantics(
                            child: BookCover(book: book, titleSize: 12),
                          ),
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => _changeCover(book),
                    child: const Text('Change cover'),
                  ),
                ],
              ),
              const SizedBox(width: Space.l),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      book.title,
                      style: theme.textTheme.headlineMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                    ),
                    if (book.author != null) ...[
                      const SizedBox(height: Space.xs),
                      Text(
                        book.author!,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: c.muted,
                        ),
                      ),
                    ],
                    const SizedBox(height: Space.m),
                    if (d != null && d.lookedUp)
                      RatingLine(
                        rating: d.rating,
                        count: d.ratingCount,
                        wantToRead: d.wantToRead,
                      ),
                    const SizedBox(height: Space.m),
                    Text(
                      entry.progress?.readLocation == null
                          ? 'Not opened yet'
                          : '${(percent * 100).round()}% read',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: Space.xs),
                    ProgressLine(
                      value: percent.clamp(0.0, 1.0),
                      color: s.primary,
                      track: s.onSurface.withValues(alpha: 0.12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: Space.l),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: s.onSurface,
                    foregroundColor: s.surface,
                  ),
                  onPressed: () => openReader(context, book),
                  icon: const Icon(Icons.chrome_reader_mode_outlined),
                  label: Text(
                    entry.progress?.readLocation == null
                        ? 'Start reading'
                        : 'Keep reading',
                  ),
                ),
              ),
              if (entry.hasAudio) ...[
                const SizedBox(width: Space.s),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => openListen(context, book),
                    icon: const Icon(Icons.headphones_outlined),
                    label: const Text('Listen'),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: Space.l),
          FactsCard(facts),
          const SizedBox(height: Space.l),
          if (entry.hasAudio)
            SaveStatus(bookId: book.id)
          else
            Card(
              child: ListTile(
                leading: const Icon(Icons.headphones_outlined),
                title: const Text('Add a free audiobook'),
                subtitle: const Text('Recordings from LibriVox volunteers'),
                trailing: const Icon(Icons.chevron_right_rounded),
                onTap: () => showAudiobookSheet(context, book),
              ),
            ),
          if (_loaded && (d == null || !d.lookedUp)) ...[
            const SizedBox(height: Space.l),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(Space.l),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Rating, description and subjects',
                      style: theme.textTheme.titleSmall,
                    ),
                    const SizedBox(height: Space.xs),
                    Text(
                      'TwoFold can ask Open Library about this title. '
                      'It sends only the title and author.',
                      style: theme.textTheme.bodySmall,
                    ),
                    const SizedBox(height: Space.m),
                    OutlinedButton.icon(
                      onPressed: _looking ? null : () => _lookUp(book),
                      icon: _looking
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.travel_explore_rounded, size: 18),
                      label: Text(_looking ? 'Looking up…' : 'Look up details'),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: Space.s),
            Text(_error!, style: theme.textTheme.bodySmall),
          ],
          if (about != null) ...[
            const SizedBox(height: Space.xl),
            AboutText(about),
          ],
          if (d != null && d.subjects.isNotEmpty) ...[
            const SizedBox(height: Space.l),
            SubjectTags(d.subjects),
          ],
          if (d != null && d.lookedUp) ...[
            const SizedBox(height: Space.xl),
            Text(openLibraryNote, style: theme.textTheme.bodySmall),
          ],
        ],
      ),
    );
  }
}
