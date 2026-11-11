import 'book_source.dart';
import 'librivox.dart';
import 'librivox_source.dart';

/// Every built-in library at once: one search box for Gutenberg, LibriVox
/// and the Internet Archive. A Gutenberg book that LibriVox recorded from is
/// one result, tagged with its recording. One request per library per tap.
class EverythingSource implements BookSource {
  EverythingSource({
    required this.gutenberg,
    required this.recordings,
    this.others = const [],
  });

  final BookSource gutenberg;
  final LibrivoxSource recordings;

  /// Searched too; their books come last (the Internet Archive).
  final List<BookSource> others;

  @override
  String get id => 'all';

  @override
  String get name => 'Everything';

  @override
  String get blurb =>
      'Project Gutenberg, LibriVox audiobooks and the Internet Archive, '
      'searched together.';

  @override
  bool get canSearch => true;

  /// Lists to browse: Gutenberg searches by subject, and new recordings.
  static const lists = [
    Shelf(id: 'g:', title: 'Popular', blurb: 'Most read this month'),
    Shelf(id: 'lv:new', title: 'New audiobooks', blurb: 'Just recorded'),
    Shelf(id: 'g:mystery', title: 'Mystery', blurb: 'Holmes, Collins, Poe'),
    Shelf(id: 'g:love stories', title: 'Romance', blurb: 'Austen, Brontë'),
    Shelf(id: 'g:adventure', title: 'Adventure', blurb: 'Verne, Stevenson'),
    Shelf(id: 'g:ghost stories', title: 'Ghost stories', blurb: 'For dark evenings'),
    Shelf(id: 'g:science fiction', title: 'Science fiction', blurb: 'Wells, Verne'),
    Shelf(id: "g:children's literature", title: 'For children', blurb: 'Oz, Peter Pan'),
  ];

  @override
  Future<List<Shelf>> shelves() async => lists;

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) async {
    if (shelf.id == 'lv:new') {
      return recordings.browse(LibrivoxSource.lists.first, page: page);
    }
    final q = shelf.id.substring(2);
    if (q.isEmpty) {
      final popular = (await gutenberg.shelves()).firstWhere(
        (s) => s.id == 'downloads',
        orElse: () => const Shelf(id: 'downloads', title: 'Popular'),
      );
      return gutenberg.browse(popular, page: page);
    }
    return gutenberg.search(q, page: page);
  }

  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    Future<FoundPage?> safe(Future<FoundPage> f) =>
        f.then<FoundPage?>((p) => p, onError: (Object _) => null);
    final answers = await Future.wait([
      safe(gutenberg.search(query, page: page)),
      safe(recordings.search(query, page: page)),
      for (final o in others) safe(o.search(query, page: page)),
    ]);
    if (answers.every((a) => a == null)) {
      // Every library failed: most likely no connection.
      return gutenberg.search(query, page: page);
    }
    final books = answers[0]?.books ?? const <FoundBook>[];
    final heard = answers[1]?.books ?? const <FoundBook>[];
    return FoundPage(
      mergeResults(
        books,
        heard,
        recordings,
        [for (final a in answers.skip(2)) ...?a?.books],
      ),
      hasMore: answers.any((a) => a?.hasMore == true),
    );
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async =>
      const <DownloadTarget>[];
}

/// Gutenberg books first, each carrying LibriVox's recording of it when
/// there is one; then recordings of books Gutenberg did not list; then the
/// rest. Books with a recording come before books without.
List<FoundBook> mergeResults(
  List<FoundBook> books,
  List<FoundBook> heard,
  LibrivoxSource recordings,
  List<FoundBook> others,
) {
  // One recording per text: the best of several (one reader, not dramatic,
  // shorter). The others are offered on the book's page.
  final byText = <String, List<LibrivoxBook>>{};
  for (final r in heard) {
    final b = recordings.recording(r.id);
    final g = b?.gutenbergId;
    if (b != null && g != null) (byText[g] ??= []).add(b);
  }
  final best = {
    for (final e in byText.entries)
      e.key: foundRecording(rankRecordings(e.value, gutenbergId: e.key).first),
  };
  final tagged = <FoundBook>[];
  final plain = <FoundBook>[];
  for (final b in books) {
    final r = best.remove(b.id);
    if (r == null) {
      plain.add(b);
    } else {
      tagged.add(withRecording(b, r));
    }
  }
  return [...tagged, ...best.values, ...plain, ...others];
}

/// [book] with the length, size and reader of recording [r].
FoundBook withRecording(FoundBook book, FoundBook r) => FoundBook(
  source: book.source,
  id: book.id,
  title: book.title,
  author: book.author ?? r.author,
  detail: book.detail,
  summary: book.summary,
  downloads: book.downloads,
  listenLength: r.listenLength,
  sizeBytes: r.sizeBytes,
  reader: r.reader,
  readerCount: r.readerCount,
  recordingId: r.id,
  // LibriVox's cover art is drawn for the recording; Gutenberg's is often a
  // plain generated page.
  coverUrl: r.coverUrl ?? book.coverUrl,
  coverAsset: book.coverAsset,
);
