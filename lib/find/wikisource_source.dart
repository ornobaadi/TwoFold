import 'dart:convert';

import 'book_source.dart';
import 'web.dart';

const _perPage = 25;

/// Wikisource's library of transcribed texts. Search uses the wiki's own
/// search; the EPUB is made on request by Wikimedia's book export tool.
class WikisourceSource extends BookSource {
  WikisourceSource(
    this._web, {
    this.language = 'en',
    this.exportBase = 'https://ws-export.wmcloud.org/',
  });

  final Web _web;
  final String language;
  final String exportBase;

  @override
  String get id => 'wikisource';

  @override
  String get name => 'Wikisource';

  @override
  String get blurb => 'Texts typed in by volunteers. Each book is made when you ask.';

  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    final url = Uri.parse('https://$language.wikisource.org/w/api.php').replace(
      queryParameters: {
        'action': 'query',
        'list': 'search',
        'srsearch': query,
        'srnamespace': '0',
        'srlimit': '$_perPage',
        'sroffset': '${page * _perPage}',
        'format': 'json',
      },
    );
    final json = jsonDecode(await _web.getText(url)) as Map<String, dynamic>;
    return FoundPage(parseWikisourceSearch(json), hasMore: json['continue'] != null);
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async => [
        DownloadTarget(
          Uri.parse(exportBase).replace(queryParameters: {
            'format': 'epub',
            'lang': language,
            'page': book.id.replaceAll(' ', '_'),
          }),
          BookFormat.epub,
        ),
      ];
}

String _plain(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), '')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&')
    .replaceAll('&#039;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Whole works. Chapters and other sub-pages ("Title/Chapter 1") are left out,
/// because the export tool makes a book from the main page.
List<FoundBook> parseWikisourceSearch(Map<String, dynamic> json) {
  final results = (json['query']?['search'] as List?) ?? const [];
  return [
    for (final r in results.cast<Map<String, dynamic>>())
      if ('${r['title']}'.isNotEmpty && !'${r['title']}'.contains('/'))
        _book('${r['title']}', _plain('${r['snippet'] ?? ''}')),
  ];
}

/// Work pages open with "Title (1894) by Kate Chopin", then page furniture. When
/// that is there it gives the author and year; otherwise the start of the text.
FoundBook _book(String title, String snippet) {
  final head = RegExp(r'\((\d{4})\)\s+by\s+(.+?)\s+\d').firstMatch(snippet);
  final text = snippet.length > 110 ? '${snippet.substring(0, 110)}…' : snippet;
  return FoundBook(
    source: 'wikisource',
    id: title,
    title: title,
    author: head?.group(2),
    detail: head != null ? head.group(1) : (text.isEmpty ? null : text),
  );
}
