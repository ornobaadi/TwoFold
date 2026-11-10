import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:twofold/find/archive_source.dart';
import 'package:twofold/find/book_info.dart';
import 'package:twofold/find/book_source.dart';
import 'package:twofold/find/gutenberg_source.dart';
import 'package:twofold/find/opds_source.dart';
import 'package:twofold/find/web.dart';
import 'package:twofold/find/wikisource_source.dart';

String _read(String name) => File('test/fixtures/find/$name').readAsStringSync();
Map<String, dynamic> _json(String name) =>
    jsonDecode(_read(name)) as Map<String, dynamic>;

/// A [Web] that never goes online and answers with what it was given.
class _FakeWeb extends Web {
  _FakeWeb(this.answers);

  final Map<String, String> answers;
  final asked = <Uri>[];

  @override
  Future<String> getText(Uri url, {int maxBytes = 4 << 20, Duration timeout = const Duration(seconds: 25)}) async {
    asked.add(url);
    final hit = answers.entries.where((e) => url.toString().contains(e.key));
    if (hit.isEmpty) throw WebError('no answer for $url');
    return hit.first.value;
  }
}

void main() {
  group('Project Gutenberg', () {
    test('a real search feed gives books, not headings', () {
      final books = parseGutenbergFeed(_read('gutenberg_search.xml'));
      expect(books, isNotEmpty);
      expect(books.first.source, 'gutenberg');
      expect(books.first.id, matches(RegExp(r'^\d+$')));
      expect(books.first.title, isNotEmpty);
      expect(books.map((b) => b.title), isNot(contains('Subjects')));
      expect(books.any((b) => b.id == '11' && b.author == 'Lewis Carroll'), isTrue);
    });

    test('searches the feed with the query and the page offset', () async {
      final web = _FakeWeb({'search.opds': _read('gutenberg_search.xml')});
      final source = GutenbergSource(web);
      await source.search('alice wonderland');
      await source.search('alice wonderland', page: 2);
      expect(web.asked.first.queryParameters, {'query': 'alice wonderland'});
      expect(web.asked.last.queryParameters['start_index'], '51');
      expect(web.asked.first.host, 'www.gutenberg.org');
    });

    test('tries the newest EPUB first and has older ones to fall back on', () async {
      final targets = await GutenbergSource(_FakeWeb({})).targets(
        const FoundBook(source: 'gutenberg', id: '11', title: 'Alice'),
      );
      expect(targets.map((t) => t.url.path), [
        '/ebooks/11.epub3.images',
        '/ebooks/11.epub.images',
        '/ebooks/11.epub.noimages',
      ]);
      expect(targets.every((t) => t.format == BookFormat.epub), isTrue);
    });
  });

  group('Internet Archive', () {
    test('a real search gives titles, tidy authors and years', () {
      final books = parseArchiveSearch(_json('archive_search.json'));
      expect(books, isNotEmpty);
      final first = books.first;
      expect(first.id, 'aliceinwonderlan00carriala');
      expect(first.author, 'Lewis Carroll');
      expect(first.detail, matches(RegExp(r'^\d{4}$')));
    });

    test('searches only free, old books and cleans the query', () async {
      final web = _FakeWeb({'advancedsearch': _read('archive_search.json')});
      final source = ArchiveSource(web);
      final page = await source.search('Alice "in" (Wonderland)! OR *');
      final q = web.asked.single.queryParameters['q']!;
      expect(q, contains('title:(Alice AND in AND Wonderland AND OR)'));
      expect(q, isNot(contains('"in"')));
      expect(q, contains('NOT collection:inlibrary'));
      expect(q, contains('NOT access-restricted-item:true'));
      expect(q, contains('date:[* TO 1930-12-31]'));
      expect(web.asked.single.queryParameters['page'], '1');
      expect(page.books, isNotEmpty);
    });

    test('a search with no words asks nothing', () async {
      final web = _FakeWeb({});
      final page = await ArchiveSource(web).search('  !! ?? ');
      expect(page.books, isEmpty);
      expect(web.asked, isEmpty);
    });

    test('picks the EPUB, then a text PDF, and never a page-image PDF', () {
      final targets = parseArchiveFiles(_json('archive_metadata.json'), 'someid');
      expect(targets.first.format, BookFormat.epub);
      expect(targets.first.url.toString(),
          'https://archive.org/download/someid/aliceinwonderlan00carriala.epub');
      expect(targets.last.format, BookFormat.pdf);

      final mixed = parseArchiveFiles({
        'files': [
          {'name': 'scan.pdf', 'format': 'Image Container PDF', 'size': '10'},
          {'name': 'sub dir/the book.epub', 'format': 'EPUB', 'size': '10'},
          {'name': 'huge.epub', 'format': 'EPUB', 'size': '${900 << 20}'},
        ],
      }, 'id');
      expect(mixed.length, 1);
      expect(mixed.single.url.toString(),
          'https://archive.org/download/id/sub%20dir/the%20book.epub');
    });
  });

  group('Wikisource', () {
    test('a real search keeps whole works and drops chapters', () {
      final books = parseWikisourceSearch(_json('wikisource_search.json'));
      expect(books, isNotEmpty);
      expect(books.every((b) => !b.title.contains('/')), isTrue);
      expect(books.any((b) => b.title == "Alice's Adventures in Wonderland"), isTrue);
      expect(books.every((b) => !(b.detail ?? '').contains('<')), isTrue);
    });

    test('drops sub-pages and strips markup from the snippet', () {
      final books = parseWikisourceSearch({
        'query': {
          'search': [
            {'title': 'Book/Chapter 1', 'snippet': 'x'},
            {
              'title': 'A Book',
              'snippet': 'The <span class="searchmatch">Story</span> &amp; &quot;more&quot;',
            },
          ],
        },
      });
      expect(books.single.title, 'A Book');
      expect(books.single.detail, 'The Story & "more"');
    });

    test('reads the author and year when the page says them', () {
      final books = parseWikisourceSearch({
        'query': {
          'search': [
            {
              'title': 'The Story of an Hour',
              'snippet': 'The <span class="searchmatch">Story</span> of an Hour (1894) '
                  'by Kate Chopin 215The Story of an Hour1894Kate Chopin Knowing that',
            },
            {'title': 'Plain Page', 'snippet': 'Just some words with no header at all'},
          ],
        },
      });
      expect(books.first.author, 'Kate Chopin');
      expect(books.first.detail, '1894');
      expect(books.last.author, isNull);
      expect(books.last.detail, 'Just some words with no header at all');
    });

    test('exports an EPUB of the page by its title', () async {
      final targets = await WikisourceSource(_FakeWeb({})).targets(
        const FoundBook(
          source: 'wikisource',
          id: 'The Story of an Hour',
          title: 'The Story of an Hour',
        ),
      );
      final url = targets.single.url;
      expect(url.host, 'ws-export.wmcloud.org');
      expect(url.queryParameters, {
        'format': 'epub',
        'lang': 'en',
        'page': 'The_Story_of_an_Hour',
      });
    });

    test('says there is more when the wiki does', () async {
      final web = _FakeWeb({'api.php': _read('wikisource_search.json')});
      final page = await WikisourceSource(web).search('alice');
      expect(page.hasMore, isTrue);
      expect(web.asked.single.host, 'en.wikisource.org');
    });
  });

  group('Lists to browse', () {
    test('Gutenberg offers Popular, Latest and Random from its own feed', () async {
      final web = _FakeWeb({'search.opds': _read('gutenberg_search.xml')});
      final source = GutenbergSource(web);
      final lists = await source.shelves();
      expect(lists.map((s) => s.title), ['Popular', 'Latest', 'Random']);
      expect(web.asked, isEmpty, reason: 'the lists are known without going online');
      final page = await source.browse(lists.first);
      await source.browse(lists[1], page: 1);
      expect(page.books, isNotEmpty);
      expect(web.asked.first.queryParameters, {'sort_order': 'downloads'});
      expect(web.asked.last.queryParameters,
          {'sort_order': 'release_date', 'start_index': '26'});
    });

    test('the real Gutenberg start page is read as those same lists', () {
      final feed = parseOpdsFeed(_read('gutenberg_root.xml'),
          Uri.parse('https://www.gutenberg.org/ebooks.opds/'));
      expect(feed.shelves.map((s) => s.title), ['Popular', 'Latest', 'Random']);
      expect(feed.shelves.first.url.toString(),
          'https://www.gutenberg.org/ebooks/search.opds/?sort_order=downloads');
      expect(feed.books, isEmpty);
      expect(feed.searchDescription.toString(),
          'https://www.gutenberg.org/catalog/osd-books.xml');
    });

    test('the Archive browses only free books, by the chosen order', () async {
      final web = _FakeWeb({'advancedsearch': _read('archive_search.json')});
      final source = ArchiveSource(web);
      final lists = await source.shelves();
      await source.browse(lists[1]);
      final q = web.asked.single.queryParameters;
      expect(q['sort[]'], 'addeddate desc');
      expect(q['q'], contains('NOT collection:inlibrary'));
      expect(q['q'], contains('date:[* TO 1930-12-31]'));
    });
  });

  group('Catalogs (OPDS)', () {
    const feed = '''<?xml version="1.0"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:dc="http://purl.org/dc/terms/">
  <title>Shelf</title>
  <link rel="next" href="/opds/all?page=2" type="application/atom+xml;profile=opds-catalog"/>
  <link rel="search" href="/opds/search?q={searchTerms}" type="application/atom+xml"/>
  <entry>
    <title>Mysteries</title>
    <id>m</id>
    <content type="text">Whodunits &amp; more</content>
    <link rel="subsection" href="/opds/mysteries" type="application/atom+xml;profile=opds-catalog;kind=acquisition"/>
  </entry>
  <entry>
    <title>The Gold Bag</title>
    <id>urn:gold</id>
    <author><name>Carolyn Wells</name></author>
    <dc:issued>1911</dc:issued>
    <summary>A detective &lt;b&gt;investigates&lt;/b&gt;.</summary>
    <link rel="http://opds-spec.org/acquisition/buy" href="/buy/gold" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition" href="/files/gold.pdf" type="application/pdf"/>
    <link rel="http://opds-spec.org/acquisition/open-access" href="https://cdn.example.net/gold.epub" type="application/epub+zip"/>
  </entry>
  <entry>
    <title>Only For Sale</title>
    <link rel="http://opds-spec.org/acquisition/buy" href="/buy/x" type="application/epub+zip"/>
  </entry>
</feed>''';

    test('reads sections, free books, the next page and search', () {
      final f = parseOpdsFeed(feed, Uri.parse('https://example.org/opds'), source: 'opds:x');
      expect(f.title, 'Shelf');
      expect(f.shelves.single.title, 'Mysteries');
      expect(f.shelves.single.blurb, 'Whodunits & more');
      expect(f.shelves.single.url.toString(), 'https://example.org/opds/mysteries');
      final book = f.books.single;
      expect(book.title, 'The Gold Bag');
      expect(book.author, 'Carolyn Wells');
      expect(book.detail, '1911');
      expect(book.summary, 'A detective investigates .');
      expect(book.downloads.map((d) => d.url.toString()), [
        'https://cdn.example.net/gold.epub',
        'https://example.org/files/gold.pdf',
      ], reason: 'EPUB first, and never the one for sale');
      expect(f.next.toString(), 'https://example.org/opds/all?page=2');
      expect(f.searchTemplate, 'https://example.org/opds/search?q={searchTerms}');
    });

    test('a catalog lists its sections, searches, pages on and allows its file sites', () async {
      final web = _FakeWeb({
        'opds/search': feed,
        'page=2': feed.replaceAll('rel="next"', 'rel="other"'),
        'example.org/opds': feed,
      });
      final source = OpdsSource(web, name: 'Shelf', root: Uri.parse('https://example.org/opds'));
      expect(web.hosts, contains('example.org'));
      final lists = await source.shelves();
      expect(lists.map((s) => s.title), ['Mysteries', 'Shelf']);
      expect(source.canSearch, isTrue);
      final page = await source.search('gold bag');
      expect(web.asked.last.toString(), 'https://example.org/opds/search?q=gold+bag');
      expect(page.hasMore, isTrue);
      final second = await source.search('gold bag', page: 1);
      expect(second.hasMore, isFalse);
      await source.targets(page.books.single);
      expect(web.hosts, contains('cdn.example.net'));
    });

    test('an OpenSearch description gives the search address', () {
      expect(
        parseOpenSearch('<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">'
            '<Url type="text/html" template="https://x.org/s?q={searchTerms}"/>'
            '<Url type="application/atom+xml" template="https://x.org/opds?q={searchTerms}&amp;p={startPage?}"/>'
            '</OpenSearchDescription>'),
        'https://x.org/opds?q={searchTerms}&p={startPage?}',
      );
    });
  });

  group('Open Library details', () {
    test('a real search gives rating, readers, pages, subjects and cover', () {
      final info = parseOpenLibrarySearch(_json('openlibrary_search.json'))!;
      expect(info.workKey, '/works/OL20078864W');
      expect(info.rating, 3.0);
      expect(info.ratingCount, 4);
      expect(info.wantToRead, 35);
      expect(info.pages, 25);
      expect(info.subjects, contains('short story'));
      expect(info.cover.toString(), 'https://covers.openlibrary.org/b/id/8750730-M.jpg');
      expect(info.page.toString(), 'https://openlibrary.org/works/OL20078864W');
    });

    test('a real work gives its description, without source notes', () {
      final text = parseWorkDescription(_json('openlibrary_work.json'))!;
      expect(text, startsWith('"The Story of an Hour" is a short story'));
      expect(parseWorkDescription({'description': 'Plain.\n----------\nSee also'}), 'Plain.');
      expect(parseWorkDescription({'description': 'A [link](https://x.org) here'}), 'A link here');
      expect(parseWorkDescription({}), isNull);
    });

    test('no match and no rating are said as such', () {
      expect(parseOpenLibrarySearch({'docs': []}), isNull);
      expect(parseOpenLibrarySearch({'docs': [{'key': '/works/X', 'ratings_average': 0}]})!.rating, isNull);
    });

    test('looks a book up once, by its title and author, and then its work', () async {
      final web = _FakeWeb({
        'search.json': _read('openlibrary_search.json'),
        'OL20078864W.json': _read('openlibrary_work.json'),
      });
      final service = BookInfoService(web);
      const book = FoundBook(source: 'gutenberg', id: '1', title: 'The Story of an Hour', author: 'Kate Chopin');
      final info = await service.lookUp(book);
      await service.lookUp(book);
      expect(web.asked.length, 2, reason: 'one search and one work, then remembered');
      expect(web.asked.first.queryParameters['title'], 'The Story of an Hour');
      expect(web.asked.first.queryParameters['author'], 'Kate Chopin');
      expect(info!.description, isNotNull);
    });

    test('big numbers are grouped', () {
      expect(groupDigits(1234567), '1,234,567');
      expect(groupDigits(12), '12');
    });
  });

  test('author names are put the way people say them', () {
    expect(tidyAuthor('Carroll, Lewis, 1832-1898'), 'Lewis Carroll');
    expect(tidyAuthor('Lewis Carroll'), 'Lewis Carroll');
    expect(tidyAuthor('Homer'), 'Homer');
    expect(tidyAuthor('Chopin, Kate'), 'Kate Chopin');
  });
}
