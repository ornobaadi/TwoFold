import 'package:twofold/app/format.dart';
import 'package:twofold/audio/timeline.dart';
import 'package:flutter_test/flutter_test.dart';

Duration s(int n) => Duration(seconds: n);

void main() {
  // Three tracks: 0-100 s, 100-160 s, 160-400 s.
  final tl = Timeline([s(100), s(60), s(240)]);

  test('total is the sum of all tracks', () {
    expect(tl.total, s(400));
  });

  test('toAbsolute adds earlier tracks and clamps', () {
    expect(tl.toAbsolute(0, s(30)), s(30));
    expect(tl.toAbsolute(1, s(10)), s(110));
    expect(tl.toAbsolute(2, s(0)), s(160));
    expect(tl.toAbsolute(1, s(999)), s(160));
    expect(tl.toAbsolute(9, s(5)), s(165));
  });

  test('fromAbsolute finds the track', () {
    expect(tl.fromAbsolute(s(30)), (index: 0, position: s(30)));
    expect(tl.fromAbsolute(s(110)), (index: 1, position: s(10)));
    expect(tl.fromAbsolute(s(300)), (index: 2, position: s(140)));
  });

  test('a boundary belongs to the next track, the book end to the last', () {
    expect(tl.fromAbsolute(s(100)), (index: 1, position: s(0)));
    expect(tl.fromAbsolute(s(400)), (index: 2, position: s(240)));
  });

  test('fromAbsolute clamps outside the book', () {
    expect(tl.fromAbsolute(s(-5)), (index: 0, position: s(0)));
    expect(tl.fromAbsolute(s(9999)), (index: 2, position: s(240)));
  });

  test('skipping crosses track boundaries', () {
    final from = tl.toAbsolute(0, s(98));
    final to = tl.fromAbsolute(tl.shift(from, s(5)));
    expect(to, (index: 1, position: s(3)));

    final back = tl.fromAbsolute(
        tl.shift(tl.toAbsolute(1, s(2)), const Duration(seconds: -5)));
    expect(back, (index: 0, position: s(97)));
  });

  test('skipping clamps at both ends of the book', () {
    expect(tl.shift(s(2), s(-5)), s(0));
    expect(tl.shift(s(398), s(5)), s(400));
  });

  test('an empty timeline is safe', () {
    final empty = Timeline(const []);
    expect(empty.toAbsolute(3, s(4)), Duration.zero);
    expect(empty.fromAbsolute(s(4)), (index: 0, position: Duration.zero));
  });

  group('formatTime', () {
    test('short and long forms, no milliseconds', () {
      expect(formatTime(const Duration(minutes: 4, seconds: 5)), '4:05');
      expect(formatTime(const Duration(hours: 1, minutes: 2, seconds: 15)),
          '1:02:15');
      expect(formatTime(const Duration(milliseconds: 999)), '0:00');
    });
  });
}
