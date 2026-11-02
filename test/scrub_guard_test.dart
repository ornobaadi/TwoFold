import 'package:twofold/audio/chapters.dart';
import 'package:twofold/audio/scrub_guard.dart';
import 'package:flutter_test/flutter_test.dart';

Duration m(int minutes) => Duration(minutes: minutes);

void main() {
  const chapters = [
    AudioChapter('1', Duration.zero),
    AudioChapter('2', Duration(minutes: 40)),
    AudioChapter('3', Duration(minutes: 80)),
  ];
  final t = DateTime(2026);

  test('a small move in the same chapter goes through', () {
    final g = ScrubGuard();
    expect(g.allow(m(25), m(25) + const Duration(seconds: 30), chapters, t), isTrue);
  });

  test('another chapter: first touch refused, second goes anywhere', () {
    final g = ScrubGuard();
    expect(g.allow(m(25), m(82), chapters, t), isFalse);
    expect(g.allow(m(25), m(85), chapters, t.add(const Duration(seconds: 2))), isTrue);
  });

  test('the second touch must come soon', () {
    final g = ScrubGuard();
    expect(g.allow(m(25), m(82), chapters, t), isFalse);
    expect(g.allow(m(25), m(82), chapters, t.add(const Duration(seconds: 6))), isFalse);
  });

  test('a small move across a chapter line still asks', () {
    final g = ScrubGuard();
    expect(
        g.allow(m(40) - const Duration(seconds: 5),
            m(40) + const Duration(seconds: 5), chapters, t),
        isFalse);
  });

  test('without chapters only distance counts', () {
    final g = ScrubGuard();
    expect(g.allow(m(1), m(1) + const Duration(seconds: 30), const [], t), isTrue);
    expect(g.allow(m(1), m(50), const [], t), isFalse);
  });

  test('after a jump the guard is back on', () {
    final g = ScrubGuard();
    g.allow(m(25), m(82), chapters, t);
    g.allow(m(25), m(82), chapters, t);
    expect(g.allow(m(82), m(10), chapters, t), isFalse);
  });
}
