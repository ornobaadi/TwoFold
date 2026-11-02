import 'chapters.dart';

/// Protects the listening position from accidental touches on the scrubber.
/// A small move goes through. A jump to another chapter, or a long way, is
/// refused the first time; a second try soon after goes wherever it points.
class ScrubGuard {
  ScrubGuard({
    this.freeRange = const Duration(seconds: 60),
    this.window = const Duration(seconds: 5),
  });

  final Duration freeRange;
  final Duration window;

  DateTime? _armedAt;

  bool get isArmed => _armedAt != null;

  void reset() => _armedAt = null;

  /// True if the seek should happen now.
  bool allow(
    Duration from,
    Duration to,
    List<AudioChapter> chapters,
    DateTime now,
  ) {
    final armed = _armedAt;
    if (armed != null && now.difference(armed) <= window) {
      _armedAt = null;
      return true;
    }
    final sameChapter = chapters.isEmpty ||
        chapterIndexAt(chapters, from) == chapterIndexAt(chapters, to);
    // Without chapters, distance alone decides.
    final near = (to - from).abs() <= freeRange;
    if (near && sameChapter) {
      _armedAt = null;
      return true;
    }
    _armedAt = now;
    return false;
  }
}
