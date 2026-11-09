import 'dart:io';

import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../data/book_repo.dart';
import '../data/models.dart';

const _addedKey = 'samples_added';

class SampleBook {
  const SampleBook(this.asset, this.title, this.author, this.reader, this.audioMs);

  final String asset;
  final String title;
  final String author;
  final String reader;
  final int audioMs;

  String get id => 'sample-$asset';
}

/// Public domain stories with LibriVox recordings, so there is something to
/// read and hear right after installing. The app has no internet, so they ship
/// inside it.
const sampleBooks = [
  SampleBook('story-of-an-hour', 'The Story of an Hour', 'Kate Chopin',
      'caseyveronica', 345088),
  SampleBook('emperors-new-clothes', "The Emperor's New Clothes",
      'Hans Christian Andersen', 'Phil Chenevert', 688041),
  SampleBook('lady-or-the-tiger', 'The Lady, or the Tiger?', 'Frank R. Stockton',
      'David Federman', 1021726),
];

/// Puts the samples in the library once, so a removed one stays removed.
/// [again] brings back any that are missing. Returns how many were added.
Future<int> addSampleBooks(BookRepo repo, {bool again = false}) async {
  if (!again && await repo.getSetting(_addedKey) == 'true') return 0;
  final docs = await getApplicationDocumentsDirectory();
  final now = DateTime.now().millisecondsSinceEpoch;
  var added = 0;
  for (final (i, s) in sampleBooks.indexed) {
    if (await repo.getBook(s.id) != null) continue;
    final dir = await Directory(p.join(docs.path, 'books', s.id)).create(recursive: true);
    Future<String> copy(String ext, String name) async {
      final data = await rootBundle.load('assets/samples/${s.asset}.$ext');
      final path = p.join(dir.path, name);
      await File(path).writeAsBytes(data.buffer.asUint8List(), flush: true);
      return path;
    }

    final book = await copy('epub', 'book.epub');
    final cover = await copy('png', 'cover.png');
    final audio = await copy('mp3', 'audio.mp3');
    await repo.insertBook(Book(
      id: s.id,
      title: s.title,
      author: s.author,
      format: 'epub',
      filePath: book,
      coverPath: cover,
      // Keeps the listed order, newest first.
      addedAt: now - i,
    ));
    await repo.setTracks(s.id, [
      AudioTrack(
        id: '${s.id}-audio',
        bookId: s.id,
        filePath: audio,
        position: 0,
        durationMs: s.audioMs,
        title: '${s.title}.mp3',
      ),
    ]);
    added++;
  }
  await repo.setSetting(_addedKey, 'true');
  return added;
}
