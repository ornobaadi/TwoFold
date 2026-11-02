/// A point where the user confirmed that page and audio match. Both are
/// fractions of the whole, from 0 to 1.
class SyncPoint {
  const SyncPoint(this.book, this.audio);

  final double book;
  final double audio;
}

/// Estimates the audio position for a place in the book, and the reverse. With
/// no confirmed points it assumes an even pace; each point the user confirms
/// makes the estimate between its neighbours much closer.
class SyncMap {
  SyncMap(List<SyncPoint> points) {
    final sorted = [...points]..sort((a, b) => a.book.compareTo(b.book));
    _points.add(const SyncPoint(0, 0));
    for (final p in sorted) {
      // A point that contradicts the ones before it can't be used.
      if (p.book > _points.last.book && p.audio > _points.last.audio &&
          p.book < 1 && p.audio < 1) {
        _points.add(p);
      }
    }
    _points.add(const SyncPoint(1, 1));
  }

  final _points = <SyncPoint>[];

  double audioAt(double book) =>
      _map(book, (p) => p.book, (p) => p.audio);

  double bookAt(double audio) =>
      _map(audio, (p) => p.audio, (p) => p.book);

  double _map(double value, double Function(SyncPoint) from,
      double Function(SyncPoint) to) {
    final v = value.clamp(0.0, 1.0);
    for (var i = 1; i < _points.length; i++) {
      final a = _points[i - 1];
      final b = _points[i];
      if (v <= from(b)) {
        final t = (v - from(a)) / (from(b) - from(a));
        return to(a) + (to(b) - to(a)) * t;
      }
    }
    return 1;
  }
}
