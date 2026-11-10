import 'package:flutter/material.dart';

enum ReaderTheme { system, paper, sepia, night }

enum ReadingFont { serif, sans }

/// The app's colour. Works with every background (Paper, Sepia, Night).
enum AppPalette {
  indigo('Indigo', Color(0xFF3F51B5)),
  forest('Forest', Color(0xFF2E6B4A)),
  clay('Clay', Color(0xFFB4532A)),
  plum('Plum', Color(0xFF7B3F6E)),
  ink('Ink', Color(0xFF2B2A27));

  const AppPalette(this.label, this.seed);

  final String label;
  final Color seed;
}

/// Colour roles for a background and a colour. Folio: paper and ink, with the
/// chosen colour used sparingly, for progress, links and the current choice.
ColorScheme schemeFor(ReaderTheme t, [AppPalette palette = AppPalette.indigo]) {
  final dark = t == ReaderTheme.night;
  final base = ColorScheme.fromSeed(
    seedColor: palette.seed,
    brightness: dark ? Brightness.dark : Brightness.light,
    dynamicSchemeVariant: palette == AppPalette.ink
        ? DynamicSchemeVariant.monochrome
        : DynamicSchemeVariant.tonalSpot,
  );
  // Near-black or parchment, leaning slightly toward the chosen colour.
  Color tint(int rgb, double amount) => Color.alphaBlend(
      palette.seed.withValues(alpha: amount), Color(0xFF000000 | rgb));
  final look = switch (t) {
    ReaderTheme.night => base.copyWith(
        surface: tint(0x121110, 0.02),
        onSurface: const Color(0xFFEDE8E0),
        onSurfaceVariant: const Color(0xFFA9A398),
        surfaceContainerLowest: tint(0x0C0B0A, 0.01),
        surfaceContainerLow: tint(0x1A1917, 0.03),
        surfaceContainer: tint(0x201F1D, 0.03),
        surfaceContainerHigh: tint(0x2A2826, 0.04),
        surfaceContainerHighest: tint(0x34322F, 0.04),
        outlineVariant: const Color(0xFF34312D),
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
    _ => base.copyWith(
        surface: const Color(0xFFFBFAF7),
        onSurface: const Color(0xFF1E1C19),
        onSurfaceVariant: const Color(0xFF6A645B),
        surfaceContainerLowest: const Color(0xFFFFFFFF),
        surfaceContainerLow: const Color(0xFFF5F3EE),
        surfaceContainer: const Color(0xFFF0EDE7),
        surfaceContainerHigh: const Color(0xFFEAE6DF),
        surfaceContainerHighest: const Color(0xFFE3DFD7),
        outlineVariant: const Color(0xFFE2DDD4),
      ),
  };
  // Folio: no tinted containers. Tonal buttons, chips and fills sit on the
  // page in quiet neutrals; only the accent itself carries colour.
  return look.copyWith(
    primaryContainer: look.surfaceContainerHigh,
    onPrimaryContainer: look.onSurface,
    secondaryContainer: look.surfaceContainerHigh,
    onSecondaryContainer: look.onSurface,
    tertiaryContainer: look.surfaceContainerHigh,
    onTertiaryContainer: look.onSurface,
  );
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
  static const double cardRadius = 16;
  static const double minTarget = 48;
}

/// Book-cloth colours (cover, lettering) for books without a cover picture.
/// They stay the same in every theme, like real bindings on a shelf.
const bookCloth = [
  (Color(0xFF7A2E2A), Color(0xFFF4E7DA)),
  (Color(0xFF2F4A3A), Color(0xFFE6EFE6)),
  (Color(0xFF2B3A55), Color(0xFFE5EAF4)),
  (Color(0xFF8A6A2F), Color(0xFFFBF1DC)),
  (Color(0xFF4A3F5C), Color(0xFFEEE8F5)),
  (Color(0xFF3B3A36), Color(0xFFEFEDE7)),
];

/// A book keeps the same cloth; the shelf gets some variety.
(Color, Color) clothFor(String title) =>
    bookCloth[title.codeUnits.fold(0, (a, b) => a + b) % bookCloth.length];

const serifFont = 'Literata';
const uiFont = 'Inter';

/// Calm motion: quick to start, soft to land, never overshooting.
const easeCurve = Curves.easeOutCubic;
const easeDuration = Duration(milliseconds: 220);

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

/// Folio's one control shape: a soft rectangle, like the corner of a book.
const _controlShape = WidgetStatePropertyAll<OutlinedBorder>(
  RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
);

ThemeData buildTheme(ReaderTheme t, [AppPalette palette = AppPalette.indigo]) {
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

  final labelLarge = ui(13, w: FontWeight.w600);
  final base = ThemeData(
    useMaterial3: true,
    colorScheme: s,
    brightness: s.brightness,
    fontFamily: uiFont,
    scaffoldBackgroundColor: s.surface,
    canvasColor: s.surface,
    dividerColor: s.outlineVariant,
    splashFactory: InkRipple.splashFactory,
  );
  // Outlined fields on the page colour: visible on any sheet or dialog.
  const fieldRadius = BorderRadius.all(Radius.circular(10));
  OutlineInputBorder field(Color c, [double w = 1]) => OutlineInputBorder(
        borderRadius: fieldRadius,
        borderSide: BorderSide(color: c, width: w),
      );

  return base.copyWith(
    extensions: [TwoFoldTokens(c)],
    textTheme: base.textTheme.copyWith(
      displaySmall: serif(28, height: 1.12),
      headlineMedium: serif(22, height: 1.2),
      titleLarge: serif(19, height: 1.25),
      titleMedium: serif(15, w: FontWeight.w600, height: 1.25),
      titleSmall: ui(13, w: FontWeight.w600),
      bodyLarge: ui(15),
      bodyMedium: ui(13),
      bodySmall: ui(11.5, color: c.muted),
      labelLarge: labelLarge,
      labelMedium: ui(12, w: FontWeight.w500, color: c.muted).copyWith(
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
      labelSmall: ui(11, w: FontWeight.w500),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(Space.minTarget, 44)),
        padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: Space.l)),
        textStyle: WidgetStatePropertyAll(labelLarge.copyWith(fontSize: 14)),
        shape: _controlShape,
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        foregroundColor: WidgetStatePropertyAll(s.onSurface),
        side: WidgetStatePropertyAll(BorderSide(color: s.outline.withValues(alpha: 0.5))),
        minimumSize: const WidgetStatePropertyAll(Size(Space.minTarget, 40)),
        textStyle: WidgetStatePropertyAll(labelLarge),
        shape: _controlShape,
      ),
    ),
    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(Space.minTarget, Space.minTarget)),
        textStyle: WidgetStatePropertyAll(labelLarge),
        shape: _controlShape,
      ),
    ),
    iconButtonTheme: IconButtonThemeData(
      style: ButtonStyle(
        minimumSize:
            const WidgetStatePropertyAll(Size(Space.minTarget, Space.minTarget)),
        shape: _controlShape,
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: s.onSurface,
      foregroundColor: s.surface,
      elevation: 1,
      focusElevation: 1,
      hoverElevation: 2,
      highlightElevation: 1,
      extendedTextStyle: ui(14, w: FontWeight.w600),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      extendedSizeConstraints: const BoxConstraints.tightFor(height: 48),
      extendedPadding: const EdgeInsets.symmetric(horizontal: Space.l),
    ),
    searchBarTheme: SearchBarThemeData(
      elevation: const WidgetStatePropertyAll(0),
      backgroundColor: WidgetStatePropertyAll(s.surfaceContainer),
      shape: const WidgetStatePropertyAll(
        RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(12))),
      ),
      hintStyle: WidgetStatePropertyAll(ui(15, color: c.muted)),
      textStyle: WidgetStatePropertyAll(ui(15)),
    ),
    chipTheme: ChipThemeData(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(color: s.outlineVariant),
      ),
      backgroundColor: s.surface,
      selectedColor: s.onSurface,
      showCheckmark: false,
      labelStyle: ui(13, w: FontWeight.w500),
      secondaryLabelStyle: ui(13, w: FontWeight.w600, color: s.surface),
      padding: const EdgeInsets.symmetric(horizontal: Space.xs, vertical: 2),
    ),
    dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: 1, space: 1),
    sliderTheme: SliderThemeData(
      // The thin classic track, not the thick Expressive one.
      // ignore: deprecated_member_use
      year2023: true,
      trackHeight: 3,
      activeTrackColor: s.primary,
      inactiveTrackColor: s.outlineVariant,
      thumbColor: s.primary,
    ),
    progressIndicatorTheme: ProgressIndicatorThemeData(
      // ignore: deprecated_member_use
      year2023: true,
      color: s.primary,
      linearTrackColor: s.outlineVariant,
      circularTrackColor: s.outlineVariant,
    ),
    switchTheme: SwitchThemeData(
      thumbColor: WidgetStateProperty.resolveWith((st) =>
          st.contains(WidgetState.selected) ? s.surface : s.outline),
      trackColor: WidgetStateProperty.resolveWith((st) =>
          st.contains(WidgetState.selected) ? s.onSurface : s.surfaceContainerHighest),
      trackOutlineColor: WidgetStateProperty.resolveWith((st) =>
          st.contains(WidgetState.selected) ? s.onSurface : s.outline.withValues(alpha: 0.5)),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
        textStyle: WidgetStatePropertyAll(labelLarge),
        shape: const WidgetStatePropertyAll(
          RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(10))),
        ),
        side: WidgetStatePropertyAll(BorderSide(color: s.outline.withValues(alpha: 0.5))),
        backgroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? s.onSurface : Colors.transparent),
        foregroundColor: WidgetStateProperty.resolveWith((st) =>
            st.contains(WidgetState.selected) ? s.surface : s.onSurface),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: s.surfaceContainerLowest,
      labelStyle: ui(14, color: c.muted),
      floatingLabelStyle: ui(13, w: FontWeight.w600, color: c.text),
      hintStyle: ui(15, color: c.muted),
      contentPadding: const EdgeInsets.symmetric(horizontal: Space.m, vertical: Space.m),
      border: field(s.outline.withValues(alpha: 0.6)),
      enabledBorder: field(s.outline.withValues(alpha: 0.6)),
      disabledBorder: field(s.outlineVariant),
      focusedBorder: field(s.onSurface, 1.5),
      errorBorder: field(s.error),
      focusedErrorBorder: field(s.error, 1.5),
    ),
    listTileTheme: ListTileThemeData(
      minVerticalPadding: Space.m,
      iconColor: s.onSurfaceVariant,
      titleTextStyle: ui(15),
      subtitleTextStyle: ui(12.5, color: c.muted),
    ),
    dialogTheme: DialogThemeData(
      backgroundColor: s.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      titleTextStyle: serif(20, height: 1.2),
      contentTextStyle: ui(13.5, color: c.muted),
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: s.surfaceContainerLow,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    ),
    appBarTheme: AppBarTheme(
      backgroundColor: s.surface,
      foregroundColor: s.onSurface,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: serif(19, height: 1.2),
    ),
    cardTheme: CardThemeData(
      color: s.surfaceContainerLow,
      elevation: 0,
      margin: EdgeInsets.zero,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(Space.cardRadius),
        side: BorderSide(color: s.outlineVariant),
      ),
    ),
    textSelectionTheme: TextSelectionThemeData(
      cursorColor: s.primary,
      selectionColor: s.primary.withValues(alpha: 0.25),
      selectionHandleColor: s.primary,
    ),
  );
}
