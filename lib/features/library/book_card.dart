import 'dart:io';

import 'package:flutter/material.dart';

import '../../app/press.dart';
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

  /// Some of its audio still plays from the internet.
  bool get streams => tracks.any((t) => t.isRemote);

  /// Its audio is all on the phone.
  bool get downloaded => hasAudio && !streams;

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
  const BookCover({super.key, required this.book, this.titleSize = 10.5});

  final Book book;
  final double titleSize;

  @override
  Widget build(BuildContext context) {
    final path = book.coverPath;
    final (bg, fg) = clothFor(book.title);
    return AspectRatio(
      aspectRatio: 2 / 3,
      child: Container(
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(Space.s),
        ),
        child: path != null && File(path).existsSync()
            ? Image.file(
                File(path),
                fit: BoxFit.cover,
                cacheWidth: 480,
                gaplessPlayback: true,
              )
            // Too small for words: the first letter, like a monogram.
            : titleSize < 8
            ? Center(
                child: Text(
                  book.title.trim().isEmpty
                      ? '?'
                      : book.title.trim().characters.first.toUpperCase(),
                  style: TextStyle(
                    fontFamily: serifFont,
                    fontSize: titleSize * 3,
                    fontWeight: FontWeight.w600,
                    color: fg,
                  ),
                ),
              )
            // Set low on the page, clear of the options button.
            : Container(
                padding: const EdgeInsets.all(Space.s),
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
    return Pressable(
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
                  if (entry.hasAudio)
                    Positioned(
                      right: 5,
                      bottom: 5,
                      child: Semantics(
                        label: entry.streams
                            ? 'Audiobook, plays online'
                            : 'Audiobook, on this phone',
                        child: Container(
                          width: 24,
                          height: 24,
                          decoration: BoxDecoration(
                            color: s.surface,
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            entry.streams
                                ? Icons.cloud_outlined
                                : Icons.headphones_rounded,
                            size: 14,
                            color: s.onSurface,
                          ),
                        ),
                      ),
                    ),
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
                              width: 26,
                              height: 26,
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
                minHeight: 3,
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
