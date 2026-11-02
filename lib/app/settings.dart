import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../audio/player_controller.dart';
import '../data/book_repo.dart';
import 'theme.dart';

enum LibrarySort { recent, title, author }

class AppSettings {
  const AppSettings({
    this.theme = ReaderTheme.system,
    this.fontSize = 18,
    this.lineHeight = 1.55,
    this.skipSeconds = 5,
    this.autoRewind = true,
    this.hintShown = false,
    this.font = ReadingFont.serif,
    this.keepScreenOn = true,
    this.sort = LibrarySort.recent,
    this.palette = AppPalette.blueberry,
  });

  final ReaderTheme theme;
  final int fontSize;
  final double lineHeight;
  final int skipSeconds;
  final bool autoRewind;
  final bool hintShown;
  final ReadingFont font;
  final bool keepScreenOn;
  final LibrarySort sort;
  final AppPalette palette;

  AppSettings copyWith({
    ReaderTheme? theme,
    int? fontSize,
    double? lineHeight,
    int? skipSeconds,
    bool? autoRewind,
    bool? hintShown,
    ReadingFont? font,
    bool? keepScreenOn,
    LibrarySort? sort,
    AppPalette? palette,
  }) =>
      AppSettings(
        theme: theme ?? this.theme,
        fontSize: fontSize ?? this.fontSize,
        lineHeight: lineHeight ?? this.lineHeight,
        skipSeconds: skipSeconds ?? this.skipSeconds,
        autoRewind: autoRewind ?? this.autoRewind,
        hintShown: hintShown ?? this.hintShown,
        font: font ?? this.font,
        keepScreenOn: keepScreenOn ?? this.keepScreenOn,
        sort: sort ?? this.sort,
        palette: palette ?? this.palette,
      );

  static Future<AppSettings> load(BookRepo repo) async {
    const d = AppSettings();
    final theme = await repo.getSetting('theme');
    return AppSettings(
      theme: ReaderTheme.values.asNameMap()[theme] ?? d.theme,
      fontSize: int.tryParse(await repo.getSetting('font_size') ?? '') ??
          d.fontSize,
      lineHeight: double.tryParse(await repo.getSetting('line_height') ?? '') ??
          d.lineHeight,
      skipSeconds: int.tryParse(await repo.getSetting('skip') ?? '') ??
          d.skipSeconds,
      autoRewind: (await repo.getSetting('auto_rewind')) != 'false',
      hintShown: (await repo.getSetting('hint_shown')) == 'true',
      font: ReadingFont.values.asNameMap()[await repo.getSetting('font')] ?? d.font,
      keepScreenOn: (await repo.getSetting('keep_screen_on')) != 'false',
      sort: LibrarySort.values.asNameMap()[await repo.getSetting('sort')] ?? d.sort,
      palette: AppPalette.values.asNameMap()[await repo.getSetting('palette')] ?? d.palette,
    );
  }

  Future<void> save(BookRepo repo) async {
    await repo.setSetting('theme', theme.name);
    await repo.setSetting('font_size', '$fontSize');
    await repo.setSetting('line_height', '$lineHeight');
    await repo.setSetting('skip', '$skipSeconds');
    await repo.setSetting('auto_rewind', '$autoRewind');
    await repo.setSetting('hint_shown', '$hintShown');
    await repo.setSetting('font', font.name);
    await repo.setSetting('keep_screen_on', '$keepScreenOn');
    await repo.setSetting('sort', sort.name);
    await repo.setSetting('palette', palette.name);
  }
}

/// Overridden in main() with the values read at startup.
final initialSettingsProvider = Provider<AppSettings>((ref) => const AppSettings());

final settingsProvider =
    NotifierProvider<SettingsNotifier, AppSettings>(SettingsNotifier.new);

class SettingsNotifier extends Notifier<AppSettings> {
  @override
  AppSettings build() => ref.watch(initialSettingsProvider);

  void change(AppSettings next) {
    state = next;
    final handler = ref.read(audioHandlerProvider);
    handler.setSkipLength(Duration(seconds: next.skipSeconds));
    handler.autoRewind = next.autoRewind;
    next.save(ref.read(bookRepoProvider));
  }
}
