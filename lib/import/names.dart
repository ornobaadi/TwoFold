import 'package:path/path.dart' as p;

/// Compares so that "Part 2" sorts before "Part 10".
int naturalCompare(String a, String b) {
  final re = RegExp(r'\d+|\D+');
  final xs = re.allMatches(a.toLowerCase()).map((m) => m[0]!).toList();
  final ys = re.allMatches(b.toLowerCase()).map((m) => m[0]!).toList();
  for (var i = 0; i < xs.length && i < ys.length; i++) {
    final x = int.tryParse(xs[i]);
    final y = int.tryParse(ys[i]);
    final c = x != null && y != null ? x.compareTo(y) : xs[i].compareTo(ys[i]);
    if (c != 0) return c;
  }
  return xs.length.compareTo(ys.length);
}

/// "the_great-book.v2.pdf" becomes "the great book.v2".
String prettifyName(String fileName) {
  final name = p.basenameWithoutExtension(fileName)
      .replaceAll(RegExp(r'[_-]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  return name.isEmpty ? fileName : name;
}

const _separator = '__';

/// Stored audio files are named `<unique>__<original name>`.
String storedAudioName(String unique, String original) =>
    '$unique$_separator$original';

/// Display title of a stored audio file.
String trackTitle(String path) {
  final base = p.basename(path);
  final i = base.indexOf(_separator);
  return prettifyName(i < 0 ? base : base.substring(i + _separator.length));
}
