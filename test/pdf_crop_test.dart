import 'dart:typed_data';

import 'package:twofold/audio/chapters.dart';
import 'package:twofold/features/player/player_bar.dart';
import 'package:twofold/features/reader/pdf_crop.dart';
import 'package:flutter_test/flutter_test.dart';

Uint8List _page(int w, int h, void Function(void Function(int, int) ink) draw) {
  final b = Uint8List(w * h * 4)..fillRange(0, w * h * 4, 255);
  draw((x, y) {
    final i = (y * w + x) * 4;
    b[i] = b[i + 1] = b[i + 2] = 0;
  });
  return b;
}

void main() {
  test('finds the ink and ignores specks', () {
    final b = _page(100, 100, (ink) {
      for (var y = 20; y < 80; y++) {
        for (var x = 25; x < 75; x++) {
          ink(x, y);
        }
      }
      ink(2, 2); // dust
    });
    final c = contentBounds(b, 100, 100)!;
    expect(c.left, closeTo(0.235, 0.001));
    expect(c.right, closeTo(0.765, 0.001));
    expect(c.top, closeTo(0.185, 0.001));
    expect(c.bottom, closeTo(0.815, 0.001));
  });

  test('a blank page has no bounds', () {
    expect(contentBounds(_page(10, 10, (_) {}), 10, 10), isNull);
  });

  const typical = CropBox(0.2, 0.2, 0.8, 0.8);

  test('normal pages share the text area, so text does not jump', () {
    expect(cropForPage(const CropBox(0.2, 0.25, 0.75, 0.5), typical), typical);
  });

  test('a cover or big figure is never cut', () {
    const cover = CropBox(0, 0, 1, 1);
    expect(cropForPage(cover, typical), cover);
  });

  test('no information falls back safely', () {
    expect(cropForPage(null, null), CropBox.full);
    expect(cropForPage(null, typical), typical);
  });

  test('the median ignores one odd page', () {
    final t = typicalCrop(const [
      CropBox(0.2, 0.2, 0.8, 0.8),
      CropBox(0.2, 0.2, 0.8, 0.8),
      CropBox(0, 0, 1, 1),
    ])!;
    expect(t, typical);
  });

  test('a crop fills the width without overflowing', () {
    final f = fitCrop(typical, 600, 900, 360, 700);
    expect(f.width, closeTo(360, 0.01));
    expect(f.height, lessThanOrEqualTo(700));
  });

  test('chapter marks skip the start and anything too close', () {
    const total = Duration(seconds: 100);
    final marks = chapterMarks(const [
      AudioChapter('a', Duration.zero),
      AudioChapter('b', Duration(seconds: 50)),
      AudioChapter('c', Duration(milliseconds: 50100)),
      AudioChapter('d', Duration(seconds: 75)),
    ], total, 300);
    expect(marks, [0.5, 0.75]);
  });
}
