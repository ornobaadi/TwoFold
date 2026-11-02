import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/bubbly.dart';
import '../../app/format.dart';
import '../../app/theme.dart';
import '../../data/models.dart';

/// A book with what the library needs to show about it.
class LibraryEntry {
  const LibraryEntry(this.book, this.progress, this.tracks);

  final Book book;
  final Progress? progress;
  final List<AudioTrack> tracks;

  bool get hasAudio => tracks.isNotEmpty;

  Duration get audioTotal => Duration(
    milliseconds: tracks.fold(0, (sum, t) => sum + (t.durationMs ?? 0)),
  );

  Duration get audioPosition {
    final p = progress;
    if (p == null) return Duration.zero;
    var ms = p.audioMs;
    for (var i = 0; i < p.trackIndex && i < tracks.length; i++) {
      ms += tracks[i].durationMs ?? 0;
    }
    return Duration(milliseconds: ms);
  }

  /// "p.33 · 15:02", "12% · 15:02" or "Not started".
  String get status {
    final parts = <String>[];
    final p = progress;
    if (p?.readLocation != null) {
      parts.add(
        book.format == 'pdf'
            ? 'p.${p!.readLocation}'
            : '${(((p!.readPercent ?? 0) * 100)).round()}%',
      );
    }
    if (audioPosition > Duration.zero) parts.add(formatTime(audioPosition));
    return parts.isEmpty ? 'Not started' : parts.join(' · ');
  }
}

/// A 2:3 cover. A book without one gets a title page in the theme's colours.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.book, this.titleSize = 11.5});

  final Book book;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final path = book.coverPath;
    // A book keeps the same colour; the shelf gets some variety.
    final (bg, fg) = switch (book.title.codeUnits.fold(0, (a, b) => a + b) %
        3) {
      0 => (s.tertiaryContainer, s.onTertiaryContainer),
      1 => (s.secondaryContainer, s.onSecondaryContainer),
      _ => (s.primary, s.onPrimary),
    };
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Space.l),
        ),
        child: path != null && File(path).existsSync()
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 480,
                gaplessPlayback: true,
              )
            // Set low on the page, clear of the options button.
            : Container(
                padding: const EdgeInsets.all(Space.s + 2),
                alignment: Alignment.bottomLeft,
                child: Text(
                  book.title,
                  maxLines: 6,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: serifFont,
                    fontSize: titleSize,
                    height: 1.25,
                    fontWeight: FontWeight.w500,
                    color: fg,
                  ),
                ),
              ),
      ),
    );
  }
}

class BookCard extends StatelessWidget {
  const BookCard({
    super.key,
    required this.entry,
    required this.onTap,
    required this.onOptions,
  });

  final LibraryEntry entry;
  final VoidCallback onTap;
  final VoidCallback onOptions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final s = theme.colorScheme;
    final percent = entry.progress?.readPercent ?? 0;
    return Bubbly(
      squish: 0.94,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onOptions,
        child: Semantics(
          button: true,
          label: '${entry.book.title}, ${entry.status}',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Stack(
                children: [
                  BookCover(book: entry.book),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Semantics(
                      button: true,
                      label: 'Options for ${entry.book.title}',
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: onOptions,
                        child: SizedBox(
                          width: Space.minTarget,
                          height: Space.minTarget,
                          child: Center(
                            child: Container(
                              width: 30,
                              height: 30,
                              decoration: BoxDecoration(
                                color: s.surfaceContainerHigh,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.more_vert_rounded,
                                size: 18,
                                color: s.onSurface,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: Space.s),
              LinearProgressIndicator(
                value: percent.clamp(0.0, 1.0),
                minHeight: 4,
                borderRadius: BorderRadius.circular(2),
              ),
              const SizedBox(height: Space.s),
              Text(
                entry.book.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall?.copyWith(height: 1.25),
              ),
              const SizedBox(height: 2),
              Text(
                entry.status,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
