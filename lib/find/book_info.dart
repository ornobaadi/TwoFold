import 'dart:convert';
import 'dart:typed_data';

import 'book_source.dart';
import 'web.dart';

/// More about a book, from Open Library: its readers' rating and the facts a
/// reader may want before getting it. Matched by title and author, so it can
/// occasionally describe another edition.
class BookInfo {
  const BookInfo({
    this.workKey,
    this.rating,
    this.ratingCount = 0,
    this.wantToRead = 0,
    this.firstYear,
    this.pages,
    this.subjects = const [],
    this.description,
    this.coverId,
  });

  /// Open Library's work, as "/works/OL123W".
  final String? workKey;

  /// Average of 1 to 5 stars, when anyone has rated it.
  final double? rating;
  final int ratingCount;
  final int wantToRead;
  final int? firstYear;
  final int? pages;
  final List<String> subjects;
  final String? description;
  final int? coverId;

  Uri? get page =>
      workKey == null ? null : Uri.parse('https://openlibrary.org$workKey');

  Uri? get cover => coverId == null
      ? null
      : Uri.parse('https://covers.openlibrary.org/b/id/$coverId-M.jpg');

  BookInfo withDescription(String? text) => BookInfo(
        workKey: workKey,
        rating: rating,
        ratingCount: ratingCount,
        wantToRead: wantToRead,
        firstYear: firstYear,
        pages: pages,
        subjects: subjects,
        description: text,
        coverId: coverId,
      );
}

const _fields = 'key,title,author_name,first_publish_year,number_of_pages_median,'
    'ratings_average,ratings_count,want_to_read_count,subject,cover_i';

/// Looks books up on Open Library, once each, only when the user opens one.
class BookInfoService {
  BookInfoService(this._web, {this.base = 'https://openlibrary.org'});

  final Web _web;
  final String base;
  final _found = <String, Future<BookInfo?>>{};
  final _covers = <Uri, Future<Uint8List?>>{};

  /// Details for [book], or null when Open Library does not know it.
  Future<BookInfo?> lookUp(FoundBook book) =>
      _found.putIfAbsent(book.key, () => _lookUp(book));

  Future<BookInfo?> _lookUp(FoundBook book) async {
    final url = Uri.parse('$base/search.json').replace(queryParameters: {
      'title': book.title,
      if (book.author != null) 'author': book.author!,
      'limit': '1',
      'fields': _fields,
    });
    final info = parseOpenLibrarySearch(
      jsonDecode(await _web.getText(url)) as Map<String, dynamic>,
    );
    if (info?.workKey == null) return info;
    try {
      final work = jsonDecode(
        await _web.getText(Uri.parse('$base${info!.workKey}.json')),
      ) as Map<String, dynamic>;
      return info.withDescription(parseWorkDescription(work));
    } on WebError {
      return info;
    }
  }

  /// The cover picture, or null if there is none to show.
  Future<Uint8List?> cover(Uri url) => _covers.putIfAbsent(url, () async {
        try {
          final bytes = await _web.getBytes(url, maxBytes: 2 << 20);
          // JPEG or PNG; anything else is not a picture we can show.
          final picture = bytes.length > 4 &&
              ((bytes[0] == 0xFF && bytes[1] == 0xD8) ||
                  (bytes[0] == 0x89 && bytes[1] == 0x50));
          return picture ? bytes : null;
        } on WebError {
          return null;
        }
      });
}

int? _int(Object? v) => v is num ? v.round() : null;

/// The first match of an Open Library search, or null if there is none.
BookInfo? parseOpenLibrarySearch(Map<String, dynamic> json) {
  final docs = (json['docs'] as List?) ?? const [];
  if (docs.isEmpty) return null;
  final d = docs.first as Map<String, dynamic>;
  final rating = d['ratings_average'];
  final subjects = ((d['subject'] as List?) ?? const [])
      .map((s) => '$s'.trim())
      .where((s) => s.isNotEmpty && s.length <= 40 && !s.contains('--'))
      .toSet()
      .take(8)
      .toList();
  return BookInfo(
    workKey: d['key'] is String ? d['key'] as String : null,
    rating: rating is num && rating > 0 ? rating.toDouble() : null,
    ratingCount: _int(d['ratings_count']) ?? 0,
    wantToRead: _int(d['want_to_read_count']) ?? 0,
    firstYear: _int(d['first_publish_year']),
    pages: _int(d['number_of_pages_median']),
    subjects: subjects,
    coverId: _int(d['cover_i']),
  );
}

/// A work's description, which Open Library gives as text or as
/// `{"value": text}`, without its trailing source notes and links.
String? parseWorkDescription(Map<String, dynamic> json) {
  final raw = json['description'];
  final text = raw is String
      ? raw
      : raw is Map
          ? '${raw['value'] ?? ''}'
          : '';
  final clean = text
      .split(RegExp(r'\n-{3,}|\n\(\[source\]|\n\[source\]'))
      .first
      .replaceAllMapped(RegExp(r'\[([^\]]+)\]\([^)]*\)'), (m) => m[1]!)
      .replaceAll(RegExp(r'\r'), '')
      .trim();
  return clean.isEmpty ? null : clean;
}

/// "1,234" for counts people read at a glance.
String groupDigits(int n) => n.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
