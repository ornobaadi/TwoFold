import 'package:flutter/foundation.dart';

import 'search.dart';

/// What the reader screen can ask a book pane to do.
abstract class ReaderActions {
  Stream<SearchHit> search(String query);
  void goTo(String location, {int highlightLength = 0});
  void goToFraction(double fraction);
}

class TocItem {
  const TocItem(this.title, this.depth, this.go);

  final String title;
  final int depth;
  final VoidCallback go;
}

/// What the EPUB and PDF panes report to the reader screen.
class PaneCallbacks {
  const PaneCallbacks({
    required this.onCenterTap,
    required this.onLocation,
    required this.onContents,
    required this.onReady,
    required this.onError,
    this.onActions,
  });

  final VoidCallback onCenterTap;

  /// Indicator text, location to save, and progress from 0 to 1.
  final void Function(String label, String location, double percent) onLocation;
  final ValueChanged<List<TocItem>> onContents;
  final VoidCallback onReady;
  final ValueChanged<String> onError;
  final ValueChanged<ReaderActions>? onActions;
}
