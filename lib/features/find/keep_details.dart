import '../../data/book_repo.dart';
import '../../data/models.dart';
import '../../find/book_info.dart';
import '../../find/book_source.dart';
import '../../find/cover_source.dart';
import '../../import/importer.dart';

/// The page for a book on its source's site, when TwoFold knows the shape.
Uri? sourcePage(FoundBook b) => switch (b.source) {
  'gutenberg' => Uri.parse('https://www.gutenberg.org/ebooks/${b.id}'),
  'archive' => Uri.parse('https://archive.org/details/${b.id}'),
  _ => null,
};

/// Open Library's facts for [bookId], plus where it came from, if known.
BookDetails detailsFrom(
  String bookId,
  BookInfo? info, {
  FoundBook? found,
  String? sourceName,
  BookDetails? before,
}) => BookDetails(
  bookId: bookId,
  source: sourceName ?? before?.source,
  sourceId: found?.id ?? before?.sourceId,
  sourceUrl: (found == null ? null : sourcePage(found))?.toString() ??
      before?.sourceUrl,
  summary: found?.summary ?? before?.summary,
  description: info?.description,
  subjects: info?.subjects ?? const [],
  rating: info?.rating,
  ratingCount: info?.ratingCount ?? 0,
  wantToRead: info?.wantToRead ?? 0,
  firstYear: info?.firstYear,
  pages: info?.pages,
  olWork: info?.workKey,
  updatedAt: DateTime.now().millisecondsSinceEpoch,
);

/// Sources whose files carry a plain generated cover, not the book's art.
const _plainCovers = {'gutenberg', 'wikisource'};

/// After a Find download: keeps the details shown in Find, and gives the book
/// Open Library's cover when its own is missing or plain. Never throws; the
/// book is already in the library and stays as it is if anything fails.
/// Returns true when the cover changed.
Future<bool> keepFindDetails({
  required BookRepo repo,
  required Importer importer,
  required CoverService covers,
  required Book book,
  required FoundBook found,
  required String sourceName,
  required Future<BookInfo?> info,
}) async {
  BookInfo? known;
  try {
    known = await info;
  } catch (_) {}
  try {
    await repo.saveDetails(
      detailsFrom(book.id, known, found: found, sourceName: sourceName),
    );
  } catch (_) {}

  final coverId = known?.coverId;
  final wanted =
      book.coverPath == null || _plainCovers.contains(found.source);
  if (coverId == null || !wanted) return false;
  try {
    final bytes = await covers.image(CoverCandidate(id: coverId).full);
    if (bytes == null) return false;
    final path = await importer.saveCoverBytes(book.id, bytes);
    await repo.setCover(book.id, path);
    return true;
  } catch (_) {
    return false;
  }
}
