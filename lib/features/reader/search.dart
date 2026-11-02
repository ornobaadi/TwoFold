/// One place in the book where the search text was found.
class SearchHit {
  const SearchHit({
    required this.snippet,
    required this.matchStart,
    required this.matchLength,
    required this.pageLabel,
    required this.location,
    required this.fraction,
    this.sourceLength = 0,
  });

  final String snippet;
  final int matchStart;
  final int matchLength;
  final String pageLabel;

  /// Same format the reader saves: `block:char` or a PDF page number.
  final String location;

  /// How far through the book, from 0 to 1.
  final double fraction;

  /// Length of the match in the original text, for highlighting.
  final int sourceLength;
}

/// Lower case, plain quotes and dashes, single spaces, and words rejoined where
/// a line break split them, with a map back to the original offsets.
({String text, List<int> map}) normalizeForSearch(String input) {
  final out = StringBuffer();
  final map = <int>[];
  var lastSpace = true;
  for (var i = 0; i < input.length; i++) {
    var ch = input[i];
    if (ch == '-' && i + 1 < input.length && input[i + 1] == '\n') {
      i++;
      continue;
    }
    ch = switch (ch) {
      '‘' || '’' => "'",
      '“' || '”' => '"',
      '–' || '—' => '-',
      _ => ch.toLowerCase(),
    };
    if (RegExp(r'\s').hasMatch(ch)) {
      if (lastSpace) continue;
      ch = ' ';
      lastSpace = true;
    } else {
      lastSpace = false;
    }
    out.write(ch);
    map.add(i);
  }
  return (text: out.toString(), map: map);
}

/// Every match of [query] in [text], as (start, length) in the original text.
List<(int, int)> findMatches(String text, String query) {
  final q = normalizeForSearch(query).text.trim();
  if (q.isEmpty) return const [];
  final n = normalizeForSearch(text);
  final out = <(int, int)>[];
  var from = 0;
  while (true) {
    final at = n.text.indexOf(q, from);
    if (at < 0) return out;
    final start = n.map[at];
    final end = n.map[at + q.length - 1] + 1;
    out.add((start, end - start));
    from = at + q.length;
  }
}

/// A line of context around a match.
SearchHit makeHit(
  String text,
  (int, int) match, {
  required String pageLabel,
  required String location,
  required double fraction,
}) {
  final (start, length) = match;
  final from = start > 50 ? start - 50 : 0;
  final to = start + length + 70 < text.length
      ? start + length + 70
      : text.length;
  final before = text.substring(from, start).replaceAll(RegExp(r'\s+'), ' ');
  final found = text
      .substring(start, start + length)
      .replaceAll(RegExp(r'\s+'), ' ');
  final after = text
      .substring(start + length, to)
      .replaceAll(RegExp(r'\s+'), ' ');
  final lead = from > 0 ? '…$before' : before;
  return SearchHit(
    snippet: '$lead$found$after${to < text.length ? '…' : ''}',
    matchStart: lead.length,
    matchLength: found.length,
    pageLabel: pageLabel,
    location: location,
    fraction: fraction,
    sourceLength: length,
  );
}
