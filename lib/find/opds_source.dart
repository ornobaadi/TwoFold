import 'package:xml/xml.dart';

import 'book_source.dart';
import 'web.dart';

/// What one page of an OPDS catalog holds.
class OpdsFeed {
  const OpdsFeed({
    this.title,
    this.shelves = const [],
    this.books = const [],
    this.next,
    this.searchTemplate,
    this.searchDescription,
  });

  final String? title;
  final List<Shelf> shelves;
  final List<FoundBook> books;
  final Uri? next;

  /// A search address with `{searchTerms}` in it.
  final String? searchTemplate;

  /// An OpenSearch description that holds the search address.
  final Uri? searchDescription;
}

const _acquisition = 'http://opds-spec.org/acquisition';

/// A catalog the user added by its link: any OPDS feed (Calibre, a library,
/// Gutenberg's own). It is browsed by its sections and searched when it says
/// how.
class OpdsSource implements BookSource {
  OpdsSource(
    this._web, {
    required this.name,
    required this.root,
    String? id,
    this.customBlurb,
    this.readTimeout = const Duration(seconds: 25),
  }) : id = id ?? 'opds:$root' {
    _web.allow(root.host);
  }

  final Web _web;
  @override
  final String name;
  final Uri root;
  @override
  final String id;

  String? _template;
  bool _rootRead = false;

  /// The next page of each list, by list and page number.
  final _pages = <String, Map<int, Uri>>{};

  @override
  String get blurb => customBlurb ?? 'Your catalog · ${root.host}';

  /// A built-in catalog's own description, instead of "Your catalog".
  final String? customBlurb;

  /// How long to wait for a list. Some catalogs are slow to build them.
  final Duration readTimeout;

  @override
  bool get canSearch => !_rootRead || _template != null;

  @override
  Future<List<Shelf>> shelves() async {
    final feed = await _read(root);
    _rootRead = true;
    _template = feed.searchTemplate;
    if (_template == null && feed.searchDescription != null) {
      try {
        _template = parseOpenSearch(await _web.getText(feed.searchDescription!));
      } on WebError {
        // Browsing still works without search.
      } on XmlException {
        // Same.
      }
    }
    // A first page that lists books right away gets one list for them.
    return [
      ...feed.shelves,
      if (feed.books.isNotEmpty)
        Shelf(id: root.toString(), title: feed.title ?? 'All books', url: root),
    ];
  }

  @override
  Future<FoundPage> browse(Shelf shelf, {int page = 0}) =>
      _page(shelf.id, shelf.url ?? Uri.parse(shelf.id), page);

  @override
  Future<FoundPage> search(String query, {int page = 0}) async {
    if (!_rootRead) await shelves();
    final template = _template;
    if (template == null) {
      throw const WebError('This catalog cannot be searched. Browse its lists instead.');
    }
    final url = root.resolve(
      template
          .replaceAll('{searchTerms}', Uri.encodeQueryComponent(query))
          .replaceAll(RegExp(r'\{[^}]*\?\}'), ''),
    );
    return _page('search:$query', url, page);
  }

  Future<FoundPage> _page(String list, Uri first, int page) async {
    final url = page == 0 ? first : _pages[list]?[page];
    if (url == null) return const FoundPage([], hasMore: false);
    final feed = await _read(url);
    if (feed.next != null) (_pages[list] ??= {})[page + 1] = feed.next!;
    return FoundPage(
      feed.books,
      hasMore: feed.next != null,
      shelves: page == 0 ? feed.shelves : const [],
    );
  }

  Future<OpdsFeed> _read(Uri url) async {
    _web.allow(url.host);
    try {
      return parseOpdsFeed(
        await _web.getText(url, timeout: readTimeout),
        url,
        source: id,
      );
    } on XmlException {
      throw const WebError('That link is not a book catalog (OPDS).');
    }
  }

  @override
  Future<List<DownloadTarget>> targets(FoundBook book) async {
    // The catalog named these files itself, so their sites may be reached.
    for (final t in book.downloads) {
      _web.allow(t.url.host);
    }
    return book.downloads;
  }
}

String? _text(XmlElement parent, String local) {
  for (final e in parent.childElements) {
    if (e.name.local == local) {
      final t = e.innerText.replaceAll(RegExp(r'\s+'), ' ').trim();
      if (t.isNotEmpty) return t;
    }
  }
  return null;
}

String _plain(String html) => html
    .replaceAll(RegExp(r'<[^>]*>'), ' ')
    .replaceAll('&amp;', '&')
    .replaceAll('&quot;', '"')
    .replaceAll('&#39;', "'")
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll(RegExp(r'\s+'), ' ')
    .trim();

/// Sections, books, the next page and how to search, from one OPDS page.
OpdsFeed parseOpdsFeed(String xml, Uri base, {String source = 'opds'}) {
  final feed = XmlDocument.parse(xml).rootElement;
  Uri? next;
  String? template;
  Uri? description;
  for (final link in feed.childElements.where((e) => e.name.local == 'link')) {
    final rel = link.getAttribute('rel') ?? '';
    final type = link.getAttribute('type') ?? '';
    final href = link.getAttribute('href');
    if (href == null) continue;
    if (rel == 'next') next = base.resolve(href);
    if (rel == 'search') {
      if (href.contains('{searchTerms}')) {
        template = base.resolve(href.split('{').first).toString() +
            href.substring(href.indexOf('{'));
      } else if (type.contains('opensearch')) {
        description = base.resolve(href);
      }
    }
  }

  final shelves = <Shelf>[];
  final books = <FoundBook>[];
  for (final entry in feed.childElements.where((e) => e.name.local == 'entry')) {
    final title = _text(entry, 'title');
    if (title == null) continue;
    final links = entry.childElements.where((e) => e.name.local == 'link').toList();
    final files = <DownloadTarget>[];
    for (final l in links) {
      final rel = l.getAttribute('rel') ?? '';
      final type = (l.getAttribute('type') ?? '').toLowerCase();
      final href = l.getAttribute('href');
      if (href == null || !rel.startsWith(_acquisition)) continue;
      // Buying, borrowing and subscribing need an account; skip them.
      if (rel != _acquisition && rel != '$_acquisition/open-access') continue;
      final format = type.contains('epub')
          ? BookFormat.epub
          : type.contains('pdf')
              ? BookFormat.pdf
              : null;
      if (format != null) files.add(DownloadTarget(base.resolve(href), format));
    }
    files.sort((a, b) => a.format.index.compareTo(b.format.index));
    final summary = _text(entry, 'summary') ?? _text(entry, 'content');
    if (files.isNotEmpty) {
      final author = entry.childElements
          .where((e) => e.name.local == 'author')
          .map((a) => _text(a, 'name'))
          .whereType<String>()
          .join(', ');
      final year = RegExp(r'\d{4}').stringMatch(
        _text(entry, 'issued') ?? _text(entry, 'published') ?? '',
      );
      books.add(FoundBook(
        source: source,
        id: _text(entry, 'id') ?? files.first.url.toString(),
        title: title,
        author: author.isEmpty ? null : author,
        detail: year,
        summary: summary == null ? null : _plain(summary),
        downloads: files,
      ));
      continue;
    }
    for (final l in links) {
      final type = l.getAttribute('type') ?? '';
      final href = l.getAttribute('href');
      if (href == null || !type.contains('atom+xml')) continue;
      final url = base.resolve(href);
      shelves.add(Shelf(
        id: url.toString(),
        title: title,
        blurb: summary == null ? null : _plain(summary),
        url: url,
      ));
      break;
    }
  }
  return OpdsFeed(
    title: _text(feed, 'title'),
    shelves: shelves,
    books: books,
    next: next,
    searchTemplate: template,
    searchDescription: description,
  );
}

/// The Atom search address from an OpenSearch description.
String? parseOpenSearch(String xml) {
  final doc = XmlDocument.parse(xml);
  for (final url in doc.descendantElements.where((e) => e.name.local == 'Url')) {
    final type = url.getAttribute('type') ?? '';
    final template = url.getAttribute('template');
    if (template != null && type.contains('atom') && template.contains('{searchTerms}')) {
      return template;
    }
  }
  return null;
}
