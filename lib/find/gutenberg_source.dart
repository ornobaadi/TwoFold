import 'package:xml/xml.dart';

import 'book_source.dart';
import 'web.dart';

const _perPage = 25;

/// Project Gutenberg, through its own catalogue feed (OPDS) for apps. Files
/// come from its normal download links.
class GutenbergSource implements BookSource {
  GutenbergSource(this._web, {this.base = 'https://www.gutenberg.org'});

  final Web _web;
  final String base;

  @override
  String get id => 'gutenberg';

  @override
  String get name => 'Project Gutenberg';

  @override
  String get blurb => 'Over 70,000 classics, free for anyone.';

  /// The lists Gutenberg's own catalogue offers on its first page.
  static const lists = [
    Shelf(id: 'downloads', title: 'Popular', blurb: 'The most downloaded books.'),
    Shelf(id: 'release_date', title: 'Latest', blurb: 'Newly added to the library.'),
    Shelf(id: 'random', title: 'Random', blurb: 'A fresh handful each time.'),
  ];

  @override
  bool get canSearch => true;

  @override
  Future<List<Shelf>> shelves() async => lists;

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) =>
      _feed({'sort_order': shelf.id}, page);

  @override
  Future<FoundPage> search(String query, {int page = 0}) =>
      _feed({'query': query}, page);

  Future<FoundPage> _feed(Map<String, String> params, int page) async {
    final url = Uri.parse('$base/ebooks/search.opds/').replace(
      queryParameters: {
        ...params,
        if (page > 0) 'start_index': '${page * _perPage + 1}',
      },
    );
    final books = parseGutenbergFeed(await _web.getText(url));
    return FoundPage(books, hasMore: books.length >= _perPage);
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => [
        // Newest format first; older books may only have the others.
        for (final suffix in const ['epub3.images', 'epub.images', 'epub.noimages'])
          DownloadTarget(Uri.parse('$base/ebooks/${book.id}.$suffix'), BookFormat.epub),
      ];
}

/// The books in a Gutenberg search feed. Other entries in the feed, such as
/// subject headings and the next-page link, are skipped.
List<FoundBook> parseGutenbergFeed(String xml) {
  final doc = XmlDocument.parse(xml);
  final out = <FoundBook>[];
  for (final entry in doc.findAllElements('entry')) {
    String? text(String tag) {
      final found = entry.findElements(tag);
      final value = found.isEmpty ? '' : found.first.innerText.trim();
      return value.isEmpty ? null : value;
    }

    final match = RegExp(r'/ebooks/(\d+)\.opds$').firstMatch(text('id') ?? '');
    final title = text('title');
    if (match == null || title == null) continue;
    out.add(FoundBook(
      source: 'gutenberg',
      id: match.group(1)!,
      title: title,
      author: text('content'),
      coverUrl: 'https://www.gutenberg.org/cache/epub/${match.group(1)}/'
          'pg${match.group(1)}.cover.medium.jpg',
    ));
  }
  return out;
}
