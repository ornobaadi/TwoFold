import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;

import 'names.dart';

bool isContentUri(String path) => path.startsWith('content://');

const audioExtensions = {
  '.mp3', '.m4a', '.m4b', '.aac', '.ogg', '.opus', '.flac', '.wav'
};

class PickedFile {
  const PickedFile({required this.uri, required this.name, this.sortKey});

  final String uri;
  final String name;

  /// Path inside a chosen folder, so "Disc 2/01" sorts after "Disc 1/12".
  final String? sortKey;

  factory PickedFile.fromMap(Map<Object?, Object?> m) => PickedFile(
        uri: m['uri'] as String,
        name: m['name'] as String,
        sortKey: m['sortKey'] as String?,
      );
}

/// Keeps the audio files of [files], in natural name order.
List<PickedFile> onlyAudio(List<PickedFile> files) => files
    .where((f) => audioExtensions.contains(p.extension(f.name).toLowerCase()))
    .toList()
  ..sort((a, b) =>
      naturalCompare(a.sortKey ?? a.name, b.sortKey ?? b.name));

/// Android's document picker and file access, through MainActivity.
class DeviceFiles {
  static const _channel = MethodChannel('twofold/files');

  static Future<List<PickedFile>> _picked(
      String method, Map<String, Object?> args) async {
    final list = await _channel.invokeListMethod<Object?>(method, args);
    return [
      for (final m in list ?? const <Object?>[])
        PickedFile.fromMap(m! as Map<Object?, Object?>),
    ];
  }

  /// Shows only EPUB and PDF files. Null if cancelled.
  static Future<PickedFile?> pickBook() async {
    final files = await _picked('pickDocuments', {
      'mimes': ['application/epub+zip', 'application/pdf'],
      'multiple': false,
    });
    return files.isEmpty ? null : files.first;
  }

  /// Shows only audio files, from wherever the user keeps them.
  static Future<List<PickedFile>> pickAudioFiles() async => onlyAudio(
        await _picked('pickDocuments', {
          'mimes': ['audio/*', 'audio/x-m4b', 'application/x-m4b'],
          'multiple': true,
        }),
      );

  /// All audio in a folder the user chooses, including subfolders.
  static Future<List<PickedFile>> pickAudioFolder() async =>
      onlyAudio(await _picked('pickFolder', const {}));

  /// Shows only images, for a book cover. Null if cancelled.
  static Future<PickedFile?> pickImage() async {
    final files = await _picked('pickDocuments', {
      'mimes': ['image/*'],
      'multiple': false,
    });
    return files.isEmpty ? null : files.first;
  }

  /// Stops the screen dimming. Does nothing where the platform can't.
  static Future<void> keepScreenOn(bool on) async {
    try {
      await _channel.invokeMethod<void>('keepScreenOn', {'on': on});
    } catch (_) {}
  }

  /// True during a phone or video call. False if that can't be told.
  static Future<bool> inCall() async {
    try {
      return await _channel.invokeMethod<bool>('inCall') ?? false;
    } catch (_) {
      return false;
    }
  }

  static Future<void> copy(String uri, String dest) =>
      _channel.invokeMethod<void>('copy', {'uri': uri, 'dest': dest});

  static Future<Uint8List> read(String uri, int offset, int length) async =>
      (await _channel.invokeMethod<Uint8List>(
          'read', {'uri': uri, 'offset': offset, 'length': length}))!;

  static Future<int> size(String uri) async =>
      (await _channel.invokeMethod<int>('size', {'uri': uri}))!;
}
