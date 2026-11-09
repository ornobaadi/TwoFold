
import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:pdfrx/pdfrx.dart';

import 'app/router.dart';
import 'app/settings.dart';
import 'app/theme.dart';
import 'audio/audio_handler.dart';
import 'audio/player_controller.dart';
import 'data/book_repo.dart';
import 'data/db.dart';
import 'features/reader/reader_screen.dart';
import 'import/samples.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled fonts' licence has to travel with them.
  LicenseRegistry.addLicense(() async* {
    for (final font in const ['Inter', 'Literata']) {
      yield LicenseEntryWithLineBreaks(
          [font], await rootBundle.loadString('assets/licenses/$font-OFL.txt'));
    }
  });
  await pdfrxFlutterInitialize();

  final repo = BookRepo(await openTwoFoldDb());
  final settings = await AppSettings.load(repo);
  final handler = await AudioService.init(
    builder: () => TwoFoldAudioHandler(repo),
    config: const AudioServiceConfig(
      androidNotificationChannelId: 'com.ornobaadi.twofold.playback',
      androidNotificationChannelName: 'Playback',
      androidNotificationOngoing: true,
      androidNotificationIcon: 'drawable/ic_stat_twofold',
    ),
  );
  handler.setSkipLength(Duration(seconds: settings.skipSeconds));
  handler.autoRewind = settings.autoRewind;

  try {
    await addSampleBooks(repo);
  } catch (_) {
    // Not worth stopping the app; the next launch tries again.
  }

  final resume = await repo.getSetting(openBookKey);

  runApp(ProviderScope(
    overrides: [
      bookRepoProvider.overrideWithValue(repo),
      audioHandlerProvider.overrideWithValue(handler),
      initialSettingsProvider.overrideWithValue(settings),
    ],
    child: TwoFoldApp(home: homeScreen(resumeBookId: resume)),
  ));
}

class TwoFoldApp extends ConsumerStatefulWidget {
  const TwoFoldApp({super.key, required this.home});

  final Widget home;

  @override
  ConsumerState<TwoFoldApp> createState() => _TwoFoldAppState();
}

class _TwoFoldAppState extends ConsumerState<TwoFoldApp> {
  static const _permissions = MethodChannel('twofold/permissions');

  @override
  void initState() {
    super.initState();
    // Android 13+ hides the media notification without this permission.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _permissions
          .invokeMethod<void>('requestNotifications')
          .catchError((Object _) {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = ref.watch(settingsProvider.select((s) => s.theme));
    final palette = ref.watch(settingsProvider.select((s) => s.palette));
    return ProgressLifecycleGuard(
      child: MaterialApp(
        title: 'TwoFold',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(theme, palette),
        darkTheme: buildTheme(ReaderTheme.night, palette),
        themeMode:
            theme == ReaderTheme.system ? ThemeMode.system : ThemeMode.light,
        themeAnimationDuration: const Duration(milliseconds: 200),
        home: widget.home,
      ),
    );
  }
}
