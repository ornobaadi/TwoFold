import 'package:audio_service/audio_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app/settings.dart';
import '../data/book_repo.dart';
import 'audio_handler.dart';
import 'downloads.dart';

/// Both are overridden in main() once the database and the audio service exist.
final bookRepoProvider = Provider<BookRepo>((ref) => throw UnimplementedError());
final audioHandlerProvider =
    Provider<TwoFoldAudioHandler>((ref) => throw UnimplementedError());

final playbackStateProvider = StreamProvider<PlaybackState>(
    (ref) => ref.watch(audioHandlerProvider).playbackState);

final mediaItemProvider = StreamProvider<MediaItem?>(
    (ref) => ref.watch(audioHandlerProvider).mediaItem);

/// Android's downloader. Tests replace it.
final downloadChannelProvider = Provider<DownloadChannel>((ref) => AndroidDownloads());

/// Saves free recordings for offline. Widgets listen to it for progress.
final downloadsProvider = Provider<AudiobookDownloads>((ref) {
  final d = AudiobookDownloads(
    ref.watch(bookRepoProvider),
    ref.watch(downloadChannelProvider),
  )..wifiOnly = ref.read(initialSettingsProvider).wifiOnlyDownloads;
  ref.onDispose(d.dispose);
  return d;
});

/// Absolute position across the whole book.
final positionProvider = StreamProvider<Duration>(
    (ref) => ref.watch(audioHandlerProvider).positionStream);

/// Saves the audio position when the app goes to the background or is
/// closed (trigger 4 of the progress-saving rules).
class ProgressLifecycleGuard extends ConsumerStatefulWidget {
  const ProgressLifecycleGuard({super.key, required this.child});

  final Widget child;

  @override
  ConsumerState<ProgressLifecycleGuard> createState() =>
      _ProgressLifecycleGuardState();
}

class _ProgressLifecycleGuardState extends ConsumerState<ProgressLifecycleGuard>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      ref.read(audioHandlerProvider).saveNow();
    }
    // Android kept downloading while we were away: take in finished parts.
    if (state == AppLifecycleState.resumed) {
      ref.read(downloadsProvider).refresh().catchError((_) {});
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
