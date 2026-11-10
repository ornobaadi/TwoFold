import 'dart:convert';

import 'book_source.dart';
import 'web.dart';

const _rows = 25;

/// Only books old enough to be free to share in the US, and never the ones the
/// Archive lends out: those can be read online but not downloaded.
const _onlyFree = 'AND NOT collection:inlibrary '
    'AND NOT access-restricted-item:true '
    'AND date:[* TO 1930-12-31]';

/// The Internet Archive's public search for books.
class ArchiveSource implements BookSource {
  ArchiveSource(this._web, {this.base = 'https://archive.org', this.maxBytes = 150 << 20});

  final Web _web;
  final String base;

  /// Files over this size are not offered.
  final int maxBytes;

  @override
  String get id => 'archive';

  @override
  String get name => 'Internet Archive';

  @override
  String get blurb => 'Books from before 1931 that anyone may download.';

  static const lists = [
    Shelf(id: 'downloads desc', title: 'Most downloaded', blurb: 'What people get most.'),
    Shelf(id: 'addeddate desc', title: 'Recently added', blurb: 'New scans of old books.'),
  ];

  @override
  bool get canSearch => true;

  @override
  Future<List<Shelf>> shelves() async => lists;

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) =>
      _query('mediatype:texts', page, sort: shelf.id);

  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    final words = searchWords(query);
    if (words.isEmpty) return const FoundPage([], hasMore: false);
    final all = words.join(' AND ');
    return _query('(title:($all) OR creator:($all)) AND mediatype:texts', page);
  }

  Future<FoundPage> _query(String what, int page, {String sort = 'downloads desc'}) async {
    final lucene = '$what AND (format:EPUB OR format:"Text PDF") $_onlyFree';
    final url = Uri.parse('$base/advancedsearch.php').replace(
      queryParameters: {
        'q': lucene,
        'fl[]': const ['identifier', 'title', 'creator', 'date'],
        'rows': '$_rows',
        'page': '${page + 1}',
        'sort[]': sort,
        'output': 'json',
      },
    );
    final json = jsonDecode(await _web.getText(url)) as Map<String, dynamic>;
    final found = parseArchiveSearch(json);
    final total = (json['response']?['numFound'] as num?)?.toInt() ?? 0;
    return FoundPage(found, hasMore: total > (page + 1) * _rows);
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async {
    final url = Uri.parse('$base/metadata/${Uri.encodeComponent(book.id)}');
    final json = jsonDecode(await _web.getText(url)) as Map<String, dynamic>;
    return parseArchiveFiles(json, book.id, base: base, maxBytes: maxBytes);
  }
}

/// The words of a search, with everything the Archive's query language treats
/// as an instruction taken out.
List<String> searchWords(String query) => query
    .replaceAll(RegExp(r'[^\p{L}\p{N}\s]', unicode: true), ' ')
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .toList();

List<FoundBook> parseArchiveSearch(Map<String, dynamic> json) {
  final docs = (json['response']?['docs'] as List?) ?? const [];
  String? first(Object? v) {
    final s = v is List ? (v.isEmpty ? null : '${v.first}') : v?.toString();
    return s == null || s.trim().isEmpty ? null : s.trim();
  }

  return [
    for (final d in docs.cast<Map<String, dynamic>>())
      if (first(d['identifier']) != null && first(d['title']) != null)
        FoundBook(
          source: 'archive',
          id: first(d['identifier'])!,
          title: first(d['title'])!,
          author: first(d['creator']) == null ? null : tidyAuthor(first(d['creator'])!),
          detail: RegExp(r'^\d{4}').stringMatch(first(d['date']) ?? ''),
        ),
  ];
}

/// The EPUB of an item if it has one, then a PDF that has real text in it. A
/// PDF that is only pictures of pages is left out.
List<DownloadTarget> parseArchiveFiles(
  Map<String, dynamic> json,
  String id, {
  String base = 'https://archive.org',
  int maxBytes = 150 << 20,
}) {
  final files = ((json['files'] as List?) ?? const []).cast<Map<String, dynamic>>();
  Uri link(String name) => Uri.parse(
        '$base/download/${Uri.encodeComponent(id)}/'
        '${name.split('/').map(Uri.encodeComponent).join('/')}',
      );

  List<DownloadTarget> pick(String format, String ext, BookFormat kind) => [
        for (final f in files)
          if (f['format'] == format &&
              '${f['name']}'.toLowerCase().endsWith(ext) &&
              (int.tryParse('${f['size']}') ?? 0) <= maxBytes)
            DownloadTarget(link('${f['name']}'), kind),
      ];

  return [
    ...pick('EPUB', '.epub', BookFormat.epub),
    ...pick('Text PDF', '.pdf', BookFormat.pdf),
  ];
}
