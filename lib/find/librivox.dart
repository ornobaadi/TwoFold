import 'dart:convert';

import 'web.dart';

/// One part of a LibriVox recording: usually a chapter or a few.
class LibrivoxPart {
  const LibrivoxPart({
    required this.title,
    required this.url,
    required this.duration,
    this.readers = const [],
  });

  final String title;

  /// The 64 kbps MP3 on archive.org, always https://archive.org/download/...
  final Uri url;
  final Duration duration;
  final List<String> readers;
}

/// A finished LibriVox recording of a book.
class LibrivoxBook {
  const LibrivoxBook({
    required this.id,
    required this.title,
    required this.authors,
    required this.language,
    required this.total,
    required this.parts,
    required this.readers,
    this.gutenbergId,
    this.pageUrl,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String language;
  final Duration total;
  final List<LibrivoxPart> parts;

  /// Everyone who reads in it, in order of first appearance.
  final List<String> readers;

  /// The Project Gutenberg book it was read from, when LibriVox says.
  final String? gutenbergId;
  final Uri? pageUrl;

  bool get solo => readers.length == 1;
  bool get dramatic => title.toLowerCase().contains('dramatic');

  /// "Chris Goringe", "Chris Goringe and Ann", or "13 readers".
  String get readerLine => switch (readers.length) {
    0 => 'LibriVox volunteers',
    1 => readers.first,
    2 => '${readers[0]} and ${readers[1]}',
    _ => '${readers.length} readers',
  };

  /// Size of the 64 kbps files: 8 KB a second.
  int get bytes => total.inSeconds * 8000;
}

/// The Gutenberg number in a link like .../etext/1342 or .../ebooks/1342.
String? gutenbergIdIn(String? url) {
  if (url == null || !url.contains('gutenberg')) return null;
  return RegExp(r'/(?:etext|ebooks)/(\d+)').firstMatch(url)?.group(1);
}

/// archive.org links in the feed come as http or www.; files are fetched
/// from https://archive.org, which is on the allowed list.
Uri? archiveUrl(String? raw) {
  if (raw == null || raw.isEmpty) return null;
  final u = Uri.tryParse(raw.trim());
  if (u == null) return null;
  final host = u.host.toLowerCase();
  if (host != 'archive.org' && host != 'www.archive.org') return null;
  return u.replace(scheme: 'https', host: 'archive.org');
}

int _int(Object? v) => v is int ? v : int.tryParse('$v') ?? 0;

/// Finished recordings in a LibriVox API answer. Recordings still being made
/// (no length, or a part without a file) are left out.
List<LibrivoxBook> parseLibrivoxFeed(Map<String, dynamic> json) {
  final books = json['books'];
  if (books is! List) return const [];
  final out = <LibrivoxBook>[];
  for (final b in books.whereType<Map<String, dynamic>>()) {
    final total = _int(b['totaltimesecs']);
    final sections = b['sections'];
    if (total <= 0 || sections is! List || sections.isEmpty) continue;
    final parts = <LibrivoxPart>[];
    final readers = <String>[];
    var complete = true;
    for (final s in sections.whereType<Map<String, dynamic>>()) {
      final url = archiveUrl(s['listen_url'] as String?);
      if (url == null) {
        complete = false;
        break;
      }
      final names = [
        for (final r in (s['readers'] as List? ?? const []))
          if (r is Map && (r['display_name'] as String?)?.trim().isNotEmpty == true)
            (r['display_name'] as String).trim(),
      ];
      for (final n in names) {
        if (!readers.contains(n)) readers.add(n);
      }
      parts.add(
        LibrivoxPart(
          title: ((s['title'] as String?) ?? '').trim().isEmpty
              ? 'Part ${parts.length + 1}'
              : (s['title'] as String).trim(),
          url: url,
          duration: Duration(seconds: _int(s['playtime'])),
          readers: names,
        ),
      );
    }
    if (!complete) continue;
    out.add(
      LibrivoxBook(
        id: '${b['id']}',
        title: ((b['title'] as String?) ?? '').trim(),
        authors: [
          for (final a in (b['authors'] as List? ?? const []))
            if (a is Map)
              [a['first_name'], a['last_name']]
                  .whereType<String>()
                  .where((s) => s.trim().isNotEmpty)
                  .join(' '),
        ],
        language: ((b['language'] as String?) ?? '').trim(),
        total: Duration(seconds: total),
        parts: parts,
        readers: readers,
        gutenbergId: gutenbergIdIn(b['url_text_source'] as String?),
        pageUrl: Uri.tryParse((b['url_librivox'] as String?) ?? ''),
      ),
    );
  }
  return out;
}

String _plain(String s) =>
    s.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), ' ').trim();

/// Best first: the same Gutenberg book, then the author, the language, one
/// reader rather than many, not a dramatic reading, then the shorter one.
List<LibrivoxBook> rankRecordings(
  List<LibrivoxBook> found, {
  String? author,
  String? gutenbergId,
  String language = 'English',
}) {
  final wantAuthor = author == null ? '' : _plain(author).split(' ').last;
  int score(LibrivoxBook b) {
    var s = 0;
    if (gutenbergId != null && b.gutenbergId == gutenbergId) s += 1000;
    if (wantAuthor.isNotEmpty &&
        b.authors.any((a) => _plain(a).split(' ').contains(wantAuthor))) {
      s += 300;
    }
    if (b.language.toLowerCase() == language.toLowerCase()) s += 100;
    if (b.solo) s += 40;
    if (b.dramatic) s -= 60;
    return s;
  }

  return [...found]..sort((a, b) {
    final d = score(b) - score(a);
    return d != 0 ? d : a.total.compareTo(b.total);
  });
}

/// Finds LibriVox recordings of a book. One request when the user asks.
class LibrivoxService {
  LibrivoxService(this._web, {this.base = 'https://librivox.org'});

  final Web _web;
  final String base;
  final _found = <String, Future<List<LibrivoxBook>>>{};

  Future<List<LibrivoxBook>> find(
    String title, {
    String? author,
    String? gutenbergId,
  }) => _found.putIfAbsent(
    '$title|$author|$gutenbergId',
    () => _find(title, author: author, gutenbergId: gutenbergId),
  );

  Future<List<LibrivoxBook>> _find(
    String title, {
    String? author,
    String? gutenbergId,
  }) async {
    // Gutenberg titles carry subtitles ("Frankenstein; or, the Modern
    // Prometheus"); LibriVox uses the short title.
    final short = title.split(RegExp(r'[;:(]')).first.trim();
    var found = await _ask('^$short');
    if (found.isEmpty) found = await _ask(short);
    final ranked = rankRecordings(
      found,
      author: author,
      gutenbergId: gutenbergId,
    );
    // Keep books by this author when the author is known.
    if (author == null) return ranked;
    final last = _plain(author).split(' ').last;
    final byAuthor = ranked
        .where((b) => b.authors.any((a) => _plain(a).contains(last)))
        .toList();
    return byAuthor.isEmpty ? ranked : byAuthor;
  }

  Future<List<LibrivoxBook>> _ask(String title) async {
    final url = Uri.parse('$base/api/feed/audiobooks/').replace(
      queryParameters: {
        'title': title,
        'format': 'json',
        'extended': '1',
        'limit': '20',
      },
    );
    try {
      final json = jsonDecode(await _web.getText(url));
      return json is Map<String, dynamic> ? parseLibrivoxFeed(json) : const [];
    } on WebError catch (e) {
      // LibriVox answers "not found" when nothing matches.
      if (e.notFound) return const [];
      _found.clear();
      rethrow;
    } on FormatException {
      return const [];
    }
  }
}
