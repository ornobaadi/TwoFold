import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../import/device_files.dart';

class AudioChapter {
  const AudioChapter(this.title, this.start);

  final String title;

  /// Absolute position in the book.
  final Duration start;
}

/// Parses the payload of an MP4 `chpl` (Nero chapters) atom.
List<AudioChapter> parseChpl(Uint8List data) {
  if (data.length < 5) return const [];
  final view = ByteData.sublistView(data);
  var o = 4; // version + flags
  if (data[0] != 0) o += 4;
  if (o >= data.length) return const [];
  final count = data[o++];
  final out = <AudioChapter>[];
  for (var i = 0; i < count && o + 9 <= data.length; i++) {
    final ticks = view.getUint64(o); // 100 ns units
    o += 8;
    final len = data[o++];
    if (o + len > data.length) break;
    final title = utf8.decode(data.sublist(o, o + len), allowMalformed: true);
    o += len;
    out.add(AudioChapter(title, Duration(microseconds: ticks ~/ 10)));
  }
  return out;
}

typedef _Read = Future<Uint8List> Function(int position, int count);

/// Reads Nero chapters from an M4B/M4A file (moov > udta > chpl). Returns an
/// empty list for anything else.
Future<List<AudioChapter>> readMp4Chapters(String path) async {
  RandomAccessFile? f;
  try {
    final _Read read;
    final int len;
    if (isContentUri(path)) {
      len = await DeviceFiles.size(path);
      read = (pos, count) => DeviceFiles.read(path, pos, count);
    } else {
      final file = f = await File(path).open();
      len = await file.length();
      read = (pos, count) async {
        await file.setPosition(pos);
        return file.read(count);
      };
    }
    final moov = await _findAtom(read, 0, len, 'moov');
    if (moov == null) return const [];
    final udta = await _findAtom(read, moov.$1, moov.$2, 'udta');
    if (udta == null) return const [];
    final chpl = await _findAtom(read, udta.$1, udta.$2, 'chpl');
    if (chpl == null || chpl.$2 - chpl.$1 > 1 << 20) return const [];
    return parseChpl(await read(chpl.$1, chpl.$2 - chpl.$1));
  } catch (_) {
    return const [];
  } finally {
    await f?.close();
  }
}

/// Finds an atom between [from] and [to]; returns its payload (start, end).
Future<(int, int)?> _findAtom(_Read read, int from, int to, String name) async {
  var pos = from;
  while (pos + 8 <= to) {
    final head = await read(pos, 8);
    if (head.length < 8) return null;
    var size = ByteData.sublistView(head).getUint32(0);
    var headSize = 8;
    if (size == 1) {
      final ext = await read(pos + 8, 8);
      if (ext.length < 8) return null;
      size = ByteData.sublistView(ext).getUint64(0);
      headSize = 16;
    } else if (size == 0) {
      size = to - pos;
    }
    if (size < headSize) return null;
    if (latin1.decode(head.sublist(4, 8)) == name) {
      return (pos + headSize, pos + size);
    }
    pos += size;
  }
  return null;
}

/// Index of the chapter containing [position], or -1 if [chapters] is empty.
int chapterIndexAt(List<AudioChapter> chapters, Duration position) {
  var found = chapters.isEmpty ? -1 : 0;
  for (var i = 0; i < chapters.length; i++) {
    if (chapters[i].start <= position) found = i;
  }
  return found;
}
