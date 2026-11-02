import 'dart:math';
import 'dart:typed_data';

/// Part of a page to show, in fractions of its width and height.
class CropBox {
  const CropBox(this.left, this.top, this.right, this.bottom);

  static const full = CropBox(0, 0, 1, 1);

  final double left;
  final double top;
  final double right;
  final double bottom;

  double get width => right - left;
  double get height => bottom - top;

  @override
  bool operator ==(Object other) =>
      other is CropBox &&
      other.left == left &&
      other.top == top &&
      other.right == right &&
      other.bottom == bottom;

  @override
  int get hashCode => Object.hash(left, top, right, bottom);

  @override
  String toString() => 'CropBox($left, $top, $right, $bottom)';
}

const _breathing = 0.015;
const _tolerance = 0.02;

/// Where the ink is on a BGRA page image, or null for a blank page. Rows and
/// columns with only a speck or two don't count, so scan dust can't undo a crop.
CropBox? contentBounds(Uint8List bgra, int width, int height) {
  final rows = List<int>.filled(height, 0);
  final cols = List<int>.filled(width, 0);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      final luma =
          (bgra[i] * 114 + bgra[i + 1] * 587 + bgra[i + 2] * 299) ~/ 1000;
      if (luma < 200) {
        rows[y]++;
        cols[x]++;
      }
    }
  }
  int? first(List<int> v) {
    for (var i = 0; i < v.length; i++) {
      if (v[i] > 1) return i;
    }
    return null;
  }

  final left = first(cols);
  final top = first(rows);
  if (left == null || top == null) return null;
  final right = cols.length - first(cols.reversed.toList())!;
  final bottom = rows.length - first(rows.reversed.toList())!;
  return CropBox(
    max(0, left / width - _breathing),
    max(0, top / height - _breathing),
    min(1, right / width + _breathing),
    min(1, bottom / height + _breathing),
  );
}

double _median(Iterable<double> values) {
  final v = values.toList()..sort();
  return v[v.length ~/ 2];
}

/// The book's typical text area, from a sample of pages.
CropBox? typicalCrop(List<CropBox> pages) {
  if (pages.isEmpty) return null;
  return CropBox(
    _median(pages.map((c) => c.left)),
    _median(pages.map((c) => c.top)),
    _median(pages.map((c) => c.right)),
    _median(pages.map((c) => c.bottom)),
  );
}

/// What to show of one page. Normal pages share the book's text area, so text
/// stays the same size and place from page to page. A page whose ink goes
/// outside it (a cover, a big figure) gets its own crop, so nothing is lost.
CropBox cropForPage(CropBox? own, CropBox? typical) {
  if (typical == null) return own ?? CropBox.full;
  if (own == null) return typical;
  final fits =
      own.left >= typical.left - _tolerance &&
      own.top >= typical.top - _tolerance &&
      own.right <= typical.right + _tolerance &&
      own.bottom <= typical.bottom + _tolerance;
  return fits ? typical : own;
}

/// Display size of a crop in a viewport: as wide as possible, without
/// overflowing, keeping the page's proportions.
({double scale, double width, double height}) fitCrop(
  CropBox crop,
  double pageWidth,
  double pageHeight,
  double viewW,
  double viewH,
) {
  final cropW = crop.width * pageWidth;
  final cropH = crop.height * pageHeight;
  final scale = min(viewW / cropW, viewH / cropH);
  return (scale: scale, width: cropW * scale, height: cropH * scale);
}
