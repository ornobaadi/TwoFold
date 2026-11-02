import 'package:flutter/material.dart';

import 'bubbly.dart';

enum ReaderTheme { system, paper, sepia, night }

enum ReadingFont { serif, sans }

/// The app's colour. Works with every background (Paper, Sepia, Night).
enum AppPalette {
  blueberry('Blueberry', Color(0xFF4F46E5)),
  ocean('Ocean', Color(0xFF0B7FD4)),
  lagoon('Lagoon', Color(0xFF00A3A3)),
  mint('Mint', Color(0xFF16B57F)),
  forest('Forest', Color(0xFF2E7D32)),
  sunshine('Sunshine', Color(0xFFF5B800)),
  ember('Ember', Color(0xFFB4532A)),
  cherry('Cherry', Color(0xFFD81B3F)),
  rose('Rose', Color(0xFFE5508E)),
  grape('Grape', Color(0xFF8E24C9)),
  graphite('Graphite', Color(0xFF5F6368));

  const AppPalette(this.label, this.seed);

  final String label;
  final Color seed;
}

/// Material colour roles for a background and a colour. The page stays quiet;
/// the containers around it carry the colour.
ColorScheme schemeFor(ReaderTheme t, [AppPalette palette = AppPalette.blueberry]) {
  final dark = t == ReaderTheme.night;
  final base = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: palette == AppPalette.graphite
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.vibrant,
  );
  // Near-black or parchment, leaning slightly toward the chosen colour.
  Color tint(int rgb, double amount) => Color.alphaBlend(
      palette.seed.withValues(alpha: amount), Color(0xFF000000 | rgb));
  return switch (t) {
    ReaderTheme.night => base.copyWith(
        surface: tint(0x121212, 0.03),
        surfaceContainerLowest: tint(0x0C0C0C, 0.02),
        surfaceContainerLow: tint(0x191919, 0.05),
        surfaceContainer: tint(0x1F1F1F, 0.07),
        surfaceContainerHigh: tint(0x292929, 0.08),
        surfaceContainerHighest: tint(0x343434, 0.09),
      ),
    ReaderTheme.sepia => base.copyWith(
        surface: const Color(0xFFF4EAD7),
        onSurface: const Color(0xFF33281C),
        onSurfaceVariant: const Color(0xFF5F5140),
        surfaceContainerLowest: const Color(0xFFFBF3E4),
        surfaceContainerLow: const Color(0xFFF0E5D0),
        surfaceContainer: const Color(0xFFEBDFC8),
        surfaceContainerHigh: const Color(0xFFE5D8BF),
        surfaceContainerHighest: const Color(0xFFDFD1B6),
        outlineVariant: const Color(0xFFD3C4A8),
      ),
    _ => base,
  };
}

/// Short names for the roles the whole app uses.
class TwoFoldColors {
  TwoFoldColors(ColorScheme s)
      : bg = s.surface,
        surface = s.surfaceContainer,
        text = s.onSurface,
        muted = s.onSurfaceVariant,
        line = s.outlineVariant,
        accent = s.primary,
        brightness = s.brightness;

  final Color bg;
  final Color surface;
  final Color text;
  final Color muted;
  final Color line;
  final Color accent;
  final Brightness brightness;
}

/// 4 dp grid.
class Space {
  static const double xs = 4, s = 8, m = 12, l = 16, xl = 24, xxl = 32;
  static const double cardRadius = 28;
  static const double minTarget = 48;
}

const serifFont = 'Literata';
const uiFont = 'Inter';

/// Expressive spatial motion: quick, with a little overshoot.
const springCurve = Cubic(0.34, 1.3, 0.64, 1);
const springDuration = Duration(milliseconds: 280);

/// Gives widgets the tokens through `context.twofold`.
class TwoFoldTokens extends ThemeExtension<TwoFoldTokens> {
  const TwoFoldTokens(this.colors);

  final TwoFoldColors colors;

  @override
  TwoFoldTokens copyWith({TwoFoldColors? colors}) =>
      TwoFoldTokens(colors ?? this.colors);

  @override
  TwoFoldTokens lerp(TwoFoldTokens? other, double t) =>
      t < 0.5 || other == null ? this : other;
}

extension TwoFoldContext on BuildContext {
  TwoFoldColors get twofold => Theme.of(this).extension<TwoFoldTokens>()!.colors;
}

/// Buttons square up as they are pressed.
WidgetStateProperty<OutlinedBorder> _morphing(double rest) =>
    WidgetStateProperty.resolveWith((states) => RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
            states.contains(WidgetState.pressed) ? rest * 0.4 : rest)));

ThemeData buildTheme(ReaderTheme t, [AppPalette palette = AppPalette.blueberry]) {
  final s = schemeFor(t == ReaderTheme.system ? ReaderTheme.paper : t, palette);
  final c = TwoFoldColors(s);

  TextStyle ui(double size, {FontWeight w = FontWeight.w400, Color? color}) =>
      TextStyle(
        fontFamily: uiFont,
        fontSize: size,
        fontWeight: w,
        color: color ?? c.text,
      );
  TextStyle serif(double size, {FontWeight w = FontWeight.w500, double? height}) =>
      TextStyle(
        fontFamily: serifFont,
        fontSize: size,
        fontWeight: w,
        height: height,
        color: c.text,
      );

  final labelLarge = ui(14, w: FontWeight.w600);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: s,
    brightness: s.brightness,
    fontFamily: uiFont,
    scaffoldBackgroundColor: s.surface,
    canvasColor: s.surface,
    dividerColor: s.outlineVariant,
    splashFactory: const BubbleSplashFactory(),
  );
  // Underline borders keep the floating label inside the filled shape.
  const fieldRadius = BorderRadius.all(Radius.circular(16));
  const field = UnderlineInputBorder(
    borderRadius: fieldRadius,
    borderSide: BorderSide.none,
  );

  return base.copyWith(
    extensions: [TwoFoldTokens(c)],
    textTheme: base.textTheme.copyWith(
      displaySmall: serif(36, height: 1.1),
      headlineMedium: serif(28, height: 1.15),
      titleLarge: serif(22, height: 1.2),
      titleMedium: ui(16, w: FontWeight.w600),
      titleSmall: ui(14, w: FontWeight.w600),
      bodyLarge: ui(16),
      bodyMedium: ui(14),
      bodySmall: ui(12, color: c.muted),
      labelLarge: labelLarge,
      labelMedium: ui(13, w: FontWeight.w500, color: c.muted).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelSmall: ui(12, w: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(Space.minTarget, 56)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Space.xl)),
        textStyle: WidgetStatePropertyAll(labelLarge.copyWith(fontSize: 16)),
        shape: _morphing(28),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(Space.minTarget, 52)),
        textStyle: WidgetStatePropertyAll(labelLarge),
        shape: _morphing(26),
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(Space.minTarget, Space.minTarget)),
        textStyle: WidgetStatePropertyAll(labelLarge),
        shape: _morphing(24),
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(Space.minTarget, Space.minTarget)),
        shape: _morphing(24),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.primaryContainer,
      foregroundColor: s.onPrimaryContainer,
      elevation: 2,
      focusElevation: 2,
      hoverElevation: 2,
      highlightElevation: 2,
      extendedTextStyle: ui(16, w: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    sliderTheme: SliderThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      activeTrackColor: s.primary,
      inactiveTrackColor: s.secondaryContainer,
      thumbColor: s.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: false,
      color: s.primary,
      linearTrackColor: s.secondaryContainer,
      circularTrackColor: s.secondaryContainer,
    ),
    switchTheme: SwitchThemeData(
      thumbIcon: WidgetStateProperty.resolveWith((states) =>
          states.contains(WidgetState.selected)
              ? const Icon(Icons.check_rounded)
              : null),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, Space.minTarget)),
        textStyle: WidgetStatePropertyAll(labelLarge),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceContainerHigh,
      labelStyle: ui(15, color: c.muted),
      hintStyle: ui(16, color: c.muted),
      border: field,
      enabledBorder: field,
      disabledBorder: field,
      focusedBorder: UnderlineInputBorder(
          borderRadius: fieldRadius,
          borderSide: BorderSide(color: s.primary, width: 2)),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: Space.m,
      iconColor: s.onSurfaceVariant,
      titleTextStyle: ui(16),
      subtitleTextStyle: ui(13, color: c.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerHigh,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      titleTextStyle: serif(24, height: 1.2),
      contentTextStyle: ui(14, color: c.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: serif(22, height: 1.2),
    ),
    cardTheme: CardThemeData(
      color: s.surfaceContainer,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(Space.cardRadius)),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.primary,
      selectionColor: s.primary.withValues(alpha: 0.25),
      selectionHandleColor: s.primary,
    ),
  );
}
