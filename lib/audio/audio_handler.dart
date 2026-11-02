import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

import '../data/book_repo.dart';
import '../data/models.dart';
import '../import/device_files.dart';
import '../import/names.dart';
import 'chapters.dart';
import 'timeline.dart';

const minSpeed = 0.75;
const maxSpeed = 2.0;
const _saveEvery = Duration(seconds: 5);
const _autoRewindAfter = Duration(seconds: 60);
const _autoRewindBy = Duration(seconds: 3);

/// Audio stays where the user keeps it (content URIs); books imported by older
/// versions have copied files.
AudioSource audioSourceFor(String path) => isContentUri(path)
    ? AudioSource.uri(Uri.parse(path))
    : AudioSource.file(path);

/// Duration of an audio file, or null if it can't be read.
Future<Duration?> probeDuration(String path) async {
  final probe = AudioPlayer();
  try {
    return await probe.setAudioSource(audioSourceFor(path));
  } catch (_) {
    return null;
  } finally {
    await probe.dispose();
  }
}

class SleepTimer {
  const SleepTimer.at(DateTime this.endsAt) : endOfChapter = false;
  const SleepTimer.chapterEnd()
      : endsAt = null,
        endOfChapter = true;

  final DateTime? endsAt;
  final bool endOfChapter;
}

/// The single audio engine of the app. Runs as a foreground service through
/// audio_service and plays all tracks of one book as one absolute timeline:
/// every position that leaves this class (notification, lock screen, UI) is
/// measured from the start of the first track.
class TwoFoldAudioHandler extends BaseAudioHandler {
  TwoFoldAudioHandler(this._repo) {
    _init();
  }

  final BookRepo _repo;

  // We handle interruptions ourselves so playback never resumes by itself
  // after a phone call (PRD section 6).
  final _player = AudioPlayer(handleInterruptions: false);

  Timeline _timeline = Timeline(const []);
  String? _bookId;
  Timer? _saveTimer;
  Timer? _sleepTimer;
  Duration? _sleepAtPosition;
  DateTime? _pausedAt;
  Duration _skip = const Duration(seconds: 5);

  bool autoRewind = true;

  /// Set while a short interruption has paused us, until when we may resume.
  DateTime? _resumeUntil;
  static const _resumeWindow = Duration(seconds: 30);

  /// Chapters of the loaded book: M4B chapters where present, otherwise one
  /// per audio file. Empty for a single file without chapters.
  final chapters = ValueNotifier<List<AudioChapter>>(const []);
  final sleep = ValueNotifier<SleepTimer?>(null);

  String? get bookId => _bookId;
  Duration get skipLength => _skip;
  Duration get total => _timeline.total;
  double get speed => _player.speed;

  Duration get absolutePosition =>
      _timeline.toAbsolute(_player.currentIndex ?? 0, _player.position);

  /// Absolute position, about every 200 ms while playing.
  Stream<Duration> get positionStream =>
      _player.positionStream.map((_) => absolutePosition);

  /// (start, end) of the chapter at [position]; the whole book if no chapters.
  (Duration, Duration) chapterBounds(Duration position) {
    final list = chapters.value;
    final i = chapterIndexAt(list, position);
    if (i < 0) return (Duration.zero, total);
    return (
      list[i].start,
      i + 1 < list.length ? list[i + 1].start : total,
    );
  }

  Future<void> _init() async {
    final session = await AudioSession.instance;
    // Not the speech preset: it asks Android to pause us for every notification
    // sound instead of lowering the volume.
    await session.configure(const AudioSessionConfiguration(
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.speech,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: false,
    ));
    session.interruptionEventStream.listen(_onInterruption);
    session.becomingNoisyEventStream.listen((_) => pause());

    _player.playbackEventStream.listen(_broadcast);
    _player.playingStream.listen(_onPlayingChanged);
    _player.positionStream.listen((_) => _checkChapterSleep());
  }

  Future<void> _onInterruption(AudioInterruptionEvent e) async {
    if (e.begin) {
      if (e.type == AudioInterruptionType.duck) {
        _player.setVolume(0.3);
        return;
      }
      // A short sound comes back by itself; a call or another app's music stays
      // paused (PRD section 6).
      final wasPlaying = _player.playing;
      final mayResume = e.type == AudioInterruptionType.pause &&
          wasPlaying &&
          !await DeviceFiles.inCall();
      await _player.pause();
      _resumeUntil =
          mayResume ? DateTime.now().add(_resumeWindow) : null;
    } else {
      if (e.type == AudioInterruptionType.duck) _player.setVolume(1.0);
      final until = _resumeUntil;
      _resumeUntil = null;
      if (until != null && DateTime.now().isBefore(until)) {
        _pausedAt = null;
        unawaited(_player.play());
      }
    }
  }

  void _onPlayingChanged(bool playing) {
    _saveTimer?.cancel();
    if (playing) {
      _saveTimer = Timer.periodic(_saveEvery, (_) => saveNow());
    } else {
      _pausedAt = DateTime.now();
      saveNow();
    }
    _broadcast(_player.playbackEvent);
  }

  void _broadcast(PlaybackEvent event) {
    playbackState.add(playbackState.value.copyWith(
      controls: [
        MediaControl.rewind,
        if (_player.playing) MediaControl.pause else MediaControl.play,
        MediaControl.fastForward,
      ],
      systemActions: const {
        MediaAction.seek,
        MediaAction.rewind,
        MediaAction.fastForward,
        MediaAction.skipToNext,
        MediaAction.skipToPrevious,
      },
      androidCompactActionIndices: const [0, 1, 2],
      processingState: const {
        ProcessingState.idle: AudioProcessingState.idle,
        ProcessingState.loading: AudioProcessingState.loading,
        ProcessingState.buffering: AudioProcessingState.buffering,
        ProcessingState.ready: AudioProcessingState.ready,
        ProcessingState.completed: AudioProcessingState.completed,
      }[_player.processingState]!,
      playing: _player.playing,
      updatePosition: absolutePosition,
      bufferedPosition: _timeline.toAbsolute(
        _player.currentIndex ?? 0,
        _player.bufferedPosition,
      ),
      speed: _player.speed,
    ));
  }

  /// Loads [book]'s playlist at its saved position, paused. Saves the book
  /// that was loaded before. Never starts playback.
  ///
  /// Opening the book that is already loaded changes nothing, so going back
  /// to a playing book keeps it playing. Pass [reload] after editing its audio.
  Future<void> loadBook(Book book, {bool reload = false}) async {
    if (_bookId == book.id && !reload) return;
    await saveNow();
    await _player.pause();
    cancelSleep();
    _bookId = null;

    final tracks = await _repo.tracksFor(book.id);
    if (tracks.isEmpty) {
      await unload();
      return;
    }

    final durations = <Duration>[];
    for (final t in tracks) {
      var ms = t.durationMs;
      if (ms == null) {
        final probed = await probeDuration(t.filePath);
        ms = probed?.inMilliseconds ?? 0;
        await _repo.setTrackDuration(t.id, ms);
      }
      durations.add(Duration(milliseconds: ms));
    }
    _timeline = Timeline(durations);
    chapters.value = _fileChapters(tracks);

    final saved = await _repo.getProgress(book.id);
    final index = (saved?.trackIndex ?? 0).clamp(0, tracks.length - 1);
    var position = Duration(milliseconds: saved?.audioMs ?? 0);
    if (position > durations[index]) position = durations[index];

    await _player.setAudioSources(
      [for (final t in tracks) audioSourceFor(t.filePath)],
      initialIndex: index,
      initialPosition: position,
    );
    await _player.setSpeed(saved?.speed ?? 1.0);

    _pausedAt = saved == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(saved.updatedAt);
    _bookId = book.id;
    mediaItem.add(MediaItem(
      id: book.id,
      title: book.title,
      artist: book.author,
      duration: _timeline.total,
      artUri: book.coverPath == null ? null : Uri.file(book.coverPath!),
    ));
    _broadcast(_player.playbackEvent);
    // Never delays opening: the list improves when this finishes.
    unawaited(_readEmbeddedChapters(book.id, tracks));
  }

  String _titleOf(AudioTrack t) => t.title ?? trackTitle(t.filePath);

  List<AudioChapter> _fileChapters(List<AudioTrack> tracks) => [
        if (tracks.length > 1)
          for (var i = 0; i < tracks.length; i++)
            AudioChapter(
                _titleOf(tracks[i]), _timeline.toAbsolute(i, Duration.zero)),
      ];

  Future<void> _readEmbeddedChapters(
      String bookId, List<AudioTrack> tracks) async {
    final out = <AudioChapter>[];
    var found = false;
    for (var i = 0; i < tracks.length; i++) {
      final start = _timeline.toAbsolute(i, Duration.zero);
      final isMp3 =
          (tracks[i].title ?? tracks[i].filePath).toLowerCase().endsWith('.mp3');
      final inner = isMp3
          ? const <AudioChapter>[]
          : await readMp4Chapters(tracks[i].filePath);
      if (inner.isEmpty) {
        out.add(AudioChapter(_titleOf(tracks[i]), start));
      } else {
        found = true;
        out.addAll(inner.map((c) => AudioChapter(c.title, start + c.start)));
      }
    }
    if (found && _bookId == bookId) chapters.value = out;
  }

  /// Stops and forgets the loaded book, e.g. when it is removed.
  Future<void> unload() async {
    _bookId = null;
    _saveTimer?.cancel();
    cancelSleep();
    await _player.stop();
    await _player.setAudioSources(const []).catchError((_) => null);
    _timeline = Timeline(const []);
    chapters.value = const [];
    mediaItem.add(null);
  }

  /// Writes the audio position of the loaded book.
  Future<void> saveNow() async {
    final id = _bookId;
    if (id == null || _timeline.isEmpty) return;
    await _repo.saveAudio(
      id,
      trackIndex: _player.currentIndex ?? 0,
      audioMs: _player.position.inMilliseconds,
      speed: _player.speed,
    );
  }

  Future<void> seekAbsolute(Duration absolute) async {
    if (_bookId == null) return;
    final t = _timeline.fromAbsolute(absolute);
    await _player.seek(t.position, index: t.index);
    await saveNow();
  }

  Future<void> skipBy(Duration delta) =>
      seekAbsolute(_timeline.shift(absolutePosition, delta));

  void setSkipLength(Duration d) => _skip = d;

  Future<void> nextChapter() async {
    final list = chapters.value;
    final i = chapterIndexAt(list, absolutePosition);
    if (i + 1 < list.length) await seekAbsolute(list[i + 1].start);
  }

  /// Back to this chapter's start, or the previous one if just past the start.
  Future<void> previousChapter() async {
    final list = chapters.value;
    final i = chapterIndexAt(list, absolutePosition);
    if (i < 0) return;
    final intoChapter = absolutePosition - list[i].start;
    final target = intoChapter < const Duration(seconds: 5) && i > 0 ? i - 1 : i;
    await seekAbsolute(list[target].start);
  }

  // --- sleep timer ---

  void sleepAfter(Duration d) {
    cancelSleep();
    sleep.value = SleepTimer.at(DateTime.now().add(d));
    _sleepTimer = Timer(d, () {
      pause();
      sleep.value = null;
    });
  }

  void sleepAtChapterEnd() {
    cancelSleep();
    _sleepAtPosition = chapterBounds(absolutePosition).$2;
    sleep.value = const SleepTimer.chapterEnd();
  }

  void cancelSleep() {
    _sleepTimer?.cancel();
    _sleepTimer = null;
    _sleepAtPosition = null;
    sleep.value = null;
  }

  void _checkChapterSleep() {
    final at = _sleepAtPosition;
    if (at == null || absolutePosition < at) return;
    pause();
    cancelSleep();
  }

  // --- audio_service callbacks (UI, lock screen, headset) ---

  @override
  Future<void> play() async {
    if (_bookId == null) return;
    if (_player.processingState == ProcessingState.completed) {
      await seekAbsolute(Duration.zero);
    } else if (autoRewind &&
        _pausedAt != null &&
        DateTime.now().difference(_pausedAt!) > _autoRewindAfter) {
      await skipBy(-_autoRewindBy);
    }
    _pausedAt = null;
    // just_audio's play() completes only when playback pauses, so don't await.
    unawaited(_player.play());
  }

  @override
  Future<void> pause() {
    _resumeUntil = null;
    return _player.pause();
  }

  @override
  Future<void> seek(Duration position) => seekAbsolute(position);

  @override
  Future<void> rewind() => skipBy(-_skip);

  @override
  Future<void> fastForward() => skipBy(_skip);

  // Headset and lock screen next/previous mean skip, as people expect from
  // audiobooks.
  @override
  Future<void> skipToNext() => fastForward();

  @override
  Future<void> skipToPrevious() => rewind();

  @override
  Future<void> setSpeed(double speed) async {
    final snapped = ((speed.clamp(minSpeed, maxSpeed)) * 20).round() / 20;
    await _player.setSpeed(snapped);
    await saveNow();
  }

  @override
  Future<void> stop() async {
    await _player.pause();
    await saveNow();
    await super.stop();
  }

  @override
  Future<void> onTaskRemoved() => saveNow();
}
