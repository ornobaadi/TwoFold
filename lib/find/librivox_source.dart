import 'dart:convert';

import 'book_source.dart';
import 'librivox.dart';
import 'web.dart';

const _perPage = 20;

/// LibriVox as a library in Find: free recordings to search by title or
/// author and to browse. Get brings the book's text from Project Gutenberg
/// (the edition LibriVox read from) and the recording comes along with it.
class LibrivoxSource implements BookSource {
  LibrivoxSource(this._web, {this.base = 'https://librivox.org', DateTime Function()? now})
    : _now = now ?? DateTime.now;

  final Web _web;
  final String base;
  final DateTime Function() _now;

  /// Recordings seen in lists and searches, by LibriVox id.
  final _seen = <String, LibrivoxBook>{};

  LibrivoxBook? recording(String id) => _seen[id];

  @override
  String get id => 'librivox';

  @override
  String get name => 'LibriVox audiobooks';

  @override
  String get blurb =>
      'Free audiobooks read by volunteers. Getting one adds the book from '
      'Project Gutenberg with its recording.';

  @override
  bool get canSearch => true;

  static const lists = [
    Shelf(id: 'new', title: 'New recordings', blurb: 'Finished in the last three months.'),
    Shelf(id: 'author:Austen', title: 'Jane Austen'),
    Shelf(id: 'author:Dickens', title: 'Charles Dickens'),
    Shelf(id: 'author:Doyle', title: 'Arthur Conan Doyle'),
    Shelf(id: 'author:Twain', title: 'Mark Twain'),
    Shelf(id: 'author:Wells', title: 'H. G. Wells'),
    Shelf(id: 'author:Verne', title: 'Jules Verne'),
    Shelf(id: 'author:Christie', title: 'Agatha Christie'),
    Shelf(id: 'author:Shelley', title: 'Mary Shelley'),
  ];

  @override
  Future<List<Shelf>> shelves() async => lists;

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) {
    if (shelf.id.startsWith('author:')) {
      return _page({'author': shelf.id.substring(7)}, page);
    }
    final since = _now().subtract(const Duration(days: 90));
    return _page({'since': '${since.millisecondsSinceEpoch ~/ 1000}'}, page);
  }

  /// By title first; a name with no title matches is tried as an author.
  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    final q = query.trim();
    final byTitle = await _page({'title': '^$q'}, page);
    if (page > 0 || byTitle.books.length >= 5) return byTitle;
    final last = q.split(RegExp(r'\s+')).last;
    final byAuthor = await _page({'author': last}, 0);
    final known = {for (final b in byTitle.books) b.id};
    return FoundPage(
      [...byTitle.books, ...byAuthor.books.where((b) => !known.contains(b.id))],
      hasMore: byTitle.hasMore,
    );
  }

  Future<FoundPage> _page(Map<String, String> params, int page) async {
    final url = Uri.parse('$base/api/feed/audiobooks/').replace(
      queryParameters: {
        ...params,
        'format': 'json',
        'extended': '1',
        'limit': '$_perPage',
        if (page > 0) 'offset': '${page * _perPage}',
      },
    );
    final List<LibrivoxBook> found;
    try {
      final json = jsonDecode(await _web.getText(url));
      found = json is Map<String, dynamic> ? parseLibrivoxFeed(json) : const [];
    } on WebError catch (e) {
      // LibriVox answers "not found" when nothing matches.
      if (e.notFound) return const FoundPage([], hasMore: false);
      rethrow;
    } on FormatException {
      return const FoundPage([], hasMore: false);
    }
    for (final b in found) {
      _seen[b.id] = b;
    }
    // Unfinished recordings are dropped by the parser, so a short page can
    // still have more after it; an empty one cannot.
    return FoundPage(
      [for (final b in found) foundRecording(b)],
      hasMore: found.isNotEmpty,
    );
  }

  /// The Gutenberg text the recording was read from.
  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async {
    final g = _seen[book.id]?.gutenbergId;
    if (g == null) {
      throw const WebError(
        'LibriVox does not say which text this was read from. '
        'Search its title in Project Gutenberg, then add the audiobook there.',
      );
    }
    return [
      for (final suffix in const ['epub3.images', 'epub.images', 'epub.noimages'])
        DownloadTarget(
          Uri.parse('https://www.gutenberg.org/ebooks/$g.$suffix'),
          BookFormat.epub,
        ),
    ];
  }
}

/// A recording as a row in Find.
FoundBook foundRecording(LibrivoxBook b) => FoundBook(
  source: 'librivox',
  id: b.id,
  title: b.title,
  author: b.authors.isEmpty ? null : b.authors.join(', '),
  detail: b.language.isNotEmpty && b.language != 'English' ? b.language : null,
  listenLength: b.total,
  sizeBytes: b.bytes,
  reader: b.readerLine,
  readerCount: b.readers.length,
);
