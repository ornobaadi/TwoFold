/// A book on one of the free sites, as a search result.
class FoundBook {
  const FoundBook({
    required this.source,
    required this.id,
    required this.title,
    this.author,
    this.detail,
    this.summary,
    this.downloads = const [],
    this.listenLength,
    this.sizeBytes,
    this.reader,
    this.readerCount = 0,
    this.recordingId,
  });

  /// [BookSource.id] of the site it came from.
  final String source;

  /// Whatever that site uses to name this book.
  final String id;
  final String title;
  final String? author;

  /// A line that helps tell editions apart: a year, or a few words of text.
  final String? detail;

  /// What the book is about, when the site says.
  final String? summary;

  /// Files the listing already named (catalogs). Empty when the site is asked
  /// for them on Get.
  final List<DownloadTarget> downloads;

  /// For a recording: how long it plays, its size and who reads it.
  final Duration? listenLength;
  final int? sizeBytes;
  final String? reader;
  final int readerCount;

  /// The LibriVox recording that comes with this book, when known.
  final String? recordingId;

  bool get isRecording => listenLength != null;

  String get key => '$source:$id';
}

class FoundPage {
  const FoundPage(this.books, {required this.hasMore, this.shelves = const []});

  final List<FoundBook> books;
  final bool hasMore;

  /// Lists inside this one (catalog sections), shown above the books.
  final List<Shelf> shelves;
}

/// A ready-made list on a site: Popular, Latest, a catalog's section.
class Shelf {
  const Shelf({required this.id, required this.title, this.blurb, this.url});

  final String id;
  final String title;
  final String? blurb;

  /// Where a catalog keeps this list.
  final Uri? url;
}

enum BookFormat {
  epub('.epub', [0x50, 0x4B, 0x03, 0x04]),
  pdf('.pdf', [0x25, 0x50, 0x44, 0x46]);

  const BookFormat(this.extension, this.magic);

  final String extension;

  /// The first bytes of every real file of this kind.
  final List<int> magic;
}

/// One file that could be this book, to try in order.
class DownloadTarget {
  const DownloadTarget(this.url, this.format);

  final Uri url;
  final BookFormat format;
}

/// A site that lists free books.
abstract class BookSource {
  String get id;
  String get name;

  /// One line for the user about what this site has.
  String get blurb;

  /// Whether [search] works for this site.
  bool get canSearch => true;

  /// The lists to browse without searching. Built-in sites answer without
  /// going online; a catalog reads its first page.
  Future<List<Shelf>> shelves() async => const [];

  /// The books on [shelf]. [page] counts from 0.
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) async =>
      const FoundPage([], hasMore: false);

  /// Results for [query]. [page] counts from 0.
  Future<FoundPage> search(String query, {int page = 0});

  /// Files to try for [book], best first. Empty if there is none to get.
  Future<List<DownloadTarget>> targets(FoundBook book);
}

/// "Carroll, Lewis, 1832-1898" becomes "Lewis Carroll".
String tidyAuthor(String raw) {
  final parts = raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
  final words = parts.where((s) => !RegExp(r'^\d{3,4}\??\s*-?').hasMatch(s)).toList();
  if (words.length >= 2) return '${words[1]} ${words[0]}';
  return words.isEmpty ? raw.trim() : words.first;
}
