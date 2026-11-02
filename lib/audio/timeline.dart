/// Maps between (track index, position in track) and one absolute position
/// across all of a book's audio files played back to back.
class Timeline {
  Timeline(List<Duration> durations) : durations = List.unmodifiable(durations) {
    var sum = Duration.zero;
    final starts = <Duration>[];
    for (final d in durations) {
      starts.add(sum);
      sum += d;
    }
    _starts = starts;
    total = sum;
  }

  final List<Duration> durations;
  late final List<Duration> _starts;
  late final Duration total;

  bool get isEmpty => durations.isEmpty;

  /// Absolute position of [position] inside track [index]. Both are clamped.
  Duration toAbsolute(int index, Duration position) {
    if (isEmpty) return Duration.zero;
    final i = index.clamp(0, durations.length - 1);
    final inTrack = _clamp(position, Duration.zero, durations[i]);
    return _starts[i] + inTrack;
  }

  /// Track and in-track position for an absolute position, clamped to the book.
  ///
  /// A position exactly on a track boundary belongs to the start of the next
  /// track, except at the very end of the book, which stays at the end of the
  /// last track.
  ({int index, Duration position}) fromAbsolute(Duration absolute) {
    if (isEmpty) return (index: 0, position: Duration.zero);
    final abs = _clamp(absolute, Duration.zero, total);
    for (var i = durations.length - 1; i >= 0; i--) {
      if (abs >= _starts[i] && (abs < _starts[i] + durations[i] || i == durations.length - 1)) {
        return (index: i, position: abs - _starts[i]);
      }
    }
    return (index: 0, position: Duration.zero);
  }

  /// [from] moved by [delta], clamped to the book.
  Duration shift(Duration from, Duration delta) =>
      _clamp(from + delta, Duration.zero, total);

  static Duration _clamp(Duration v, Duration lo, Duration hi) =>
      v < lo ? lo : (v > hi ? hi : v);
}
