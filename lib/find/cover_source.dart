import 'dart:convert';
import 'dart:typed_data';

import 'web.dart';

/// One cover the user can pick for a book.
class CoverCandidate {
  const CoverCandidate({required this.id, this.label});

  /// Open Library's cover id.
  final int id;

  /// Which edition it belongs to: a year and publisher, when known.
  final String? label;

  Uri get thumb => Uri.parse('https://covers.openlibrary.org/b/id/$id-M.jpg');
  Uri get full => Uri.parse('https://covers.openlibrary.org/b/id/$id-L.jpg');
}

/// The work for a title and author, as "/works/OL123W", and its main cover.
({String? work, int? cover}) parseWorkSearch(Map<String, dynamic> json) {
  final docs = json['docs'];
  if (docs is! List || docs.isEmpty) return (work: null, cover: null);
  final d = docs.first as Map<String, dynamic>;
  final cover = d['cover_i'];
  return (
    work: d['key'] as String?,
    cover: cover is int && cover > 0 ? cover : null,
  );
}

/// Every cover of every edition in an `editions.json` page, each once, with
/// the edition's year and publisher. Open Library marks missing covers with
/// negative ids.
List<CoverCandidate> parseEditionCovers(
  Map<String, dynamic> json, {
  int? first,
}) {
  final out = <CoverCandidate>[];
  final seen = <int>{};
  if (first != null) {
    out.add(CoverCandidate(id: first, label: 'Most used'));
    seen.add(first);
  }
  final entries = json['entries'];
  if (entries is! List) return out;
  for (final e in entries.whereType<Map<String, dynamic>>()) {
    final covers = e['covers'];
    if (covers is! List) continue;
    final year = RegExp(r'\d{4}').firstMatch('${e['publish_date'] ?? ''}')?[0];
    final publishers = e['publishers'];
    final publisher = publishers is List && publishers.isNotEmpty
        ? '${publishers.first}'
        : null;
    final label = [?year, ?publisher].join(' · ');
    for (final c in covers) {
      if (c is! int || c <= 0 || !seen.add(c)) continue;
      out.add(CoverCandidate(id: c, label: label.isEmpty ? null : label));
    }
  }
  return out;
}

/// True for a real JPEG or PNG big enough to be a cover. Open Library sends
/// a tiny blank image for covers it does not have.
bool looksLikeCover(Uint8List bytes) {
  if (bytes.length < 2000) return false;
  final jpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
  final png = bytes[0] == 0x89 && bytes[1] == 0x50 && bytes[2] == 0x4E;
  return jpeg || png;
}

/// Finds covers on Open Library: one search for the work, one for its
/// editions, only when the user asks for covers. Images go through the same
/// strict client as everything else in Find.
class CoverService {
  CoverService(this._web, {this.base = 'https://openlibrary.org'});

  final Web _web;
  final String base;
  final _images = <Uri, Future<Uint8List?>>{};

  Future<List<CoverCandidate>> search(String title, String? author) async {
    final found = parseWorkSearch(
      jsonDecode(
            await _web.getText(
              Uri.parse('$base/search.json').replace(
                queryParameters: {
                  'title': title,
                  if (author != null && author.isNotEmpty) 'author': author,
                  'limit': '1',
                  'fields': 'key,cover_i',
                },
              ),
            ),
          )
          as Map<String, dynamic>,
    );
    final work = found.work;
    if (work == null) return const [];
    final editions =
        jsonDecode(
              await _web.getText(
                Uri.parse('$base$work/editions.json?limit=100'),
              ),
            )
            as Map<String, dynamic>;
    return parseEditionCovers(editions, first: found.cover).take(30).toList();
  }

  /// A cover's image, remembered while the app runs. Null when it is missing.
  Future<Uint8List?> image(Uri url) => _images.putIfAbsent(url, () async {
    try {
      final bytes = await _web.getBytes(url, maxBytes: 5 * 1024 * 1024);
      return looksLikeCover(bytes) ? bytes : null;
    } on WebError {
      _images.remove(url);
      rethrow;
    }
  });
}
