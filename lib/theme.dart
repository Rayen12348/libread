import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The Tokyo Night palette, in its three official variants.
///
/// Values are taken from the reference colour scheme so the app matches the
/// editor theme of the same name.
class TokyoNight {
  const TokyoNight._();

  // --- Night (the default, darkest variant) ---
  static const nightBg = Color(0xFF1A1B26);
  static const nightBgDark = Color(0xFF16161E);
  static const nightSurface = Color(0xFF1F2335);
  static const nightSurfaceHigh = Color(0xFF24283B);
  static const nightHighlight = Color(0xFF292E42);
  static const nightGutter = Color(0xFF3B4261);

  // --- Storm (lighter dark variant) ---
  static const stormBg = Color(0xFF24283B);
  static const stormBgDark = Color(0xFF1F2335);
  static const stormSurface = Color(0xFF2A2F45);
  static const stormSurfaceHigh = Color(0xFF30354E);
  static const stormHighlight = Color(0xFF343A55);
  static const stormGutter = Color(0xFF3B4261);

  // --- Shared accents (dark variants) ---
  static const fg = Color(0xFFC0CAF5);
  static const fgDark = Color(0xFFA9B1D6);
  static const comment = Color(0xFF565F89);
  static const dark3 = Color(0xFF545C7E);
  static const dark5 = Color(0xFF737AA2);

  static const blue = Color(0xFF7AA2F7);
  static const blue0 = Color(0xFF3D59A1);
  static const cyan = Color(0xFF7DCFFF);
  static const teal = Color(0xFF1ABC9C);
  static const magenta = Color(0xFFBB9AF7);
  static const purple = Color(0xFF9D7CD8);
  static const orange = Color(0xFFFF9E64);
  static const yellow = Color(0xFFE0AF68);
  static const green = Color(0xFF9ECE6A);
  static const green1 = Color(0xFF73DACA);
  static const red = Color(0xFFF7768E);
  static const red1 = Color(0xFFDB4B4B);

  // --- Day (light variant) ---
  static const dayBg = Color(0xFFE1E2E7);
  static const daySurface = Color(0xFFD5D6DB);
  static const dayCard = Color(0xFFE9E9ED);
  static const dayFg = Color(0xFF3760BF);
  static const dayComment = Color(0xFF848CB5);
  static const dayBlue = Color(0xFF2E7DE9);
  static const dayCyan = Color(0xFF007197);
  static const dayMagenta = Color(0xFF9854F1);
  static const dayOrange = Color(0xFFB15C00);
  static const dayGreen = Color(0xFF587539);
  static const dayRed = Color(0xFFF52A65);

  /// Accents used to tint generated covers and source badges, in palette order.
  static const accents = <Color>[
    blue,
    magenta,
    green1,
    orange,
    green,
    cyan,
    purple,
    yellow,
    red,
    teal,
  ];
}

/// Which Tokyo Night variant the app renders in.
enum AppTheme {
  night('Tokyo Night', 'The classic deep-blue dark theme'),
  storm('Tokyo Night Storm', 'A softer, lighter dark theme'),
  day('Tokyo Night Day', 'The light theme'),
  system('Follow system', 'Night when dark, Day when light');

  const AppTheme(this.label, this.blurb);

  final String label;
  final String blurb;
}

/// Builds the [ThemeData] for each Tokyo Night variant.
class AppThemes {
  const AppThemes._();

  static ThemeData night() => _dark(
    bg: TokyoNight.nightBg,
    bgDark: TokyoNight.nightBgDark,
    surface: TokyoNight.nightSurface,
    surfaceHigh: TokyoNight.nightSurfaceHigh,
    highlight: TokyoNight.nightHighlight,
    gutter: TokyoNight.nightGutter,
  );

  static ThemeData storm() => _dark(
    bg: TokyoNight.stormBg,
    bgDark: TokyoNight.stormBgDark,
    surface: TokyoNight.stormSurface,
    surfaceHigh: TokyoNight.stormSurfaceHigh,
    highlight: TokyoNight.stormHighlight,
    gutter: TokyoNight.stormGutter,
  );

  /// System chrome overlay matching a theme, so the status bar icons stay legible.
  static SystemUiOverlayStyle overlayFor(ThemeData theme) {
    final dark = theme.brightness == Brightness.dark;
    return SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: dark ? Brightness.light : Brightness.dark,
      statusBarBrightness: dark ? Brightness.dark : Brightness.light,
      systemNavigationBarColor: theme.colorScheme.surface,
      systemNavigationBarIconBrightness: dark ? Brightness.light : Brightness.dark,
    );
  }

  static ThemeData _dark({
    required Color bg,
    required Color bgDark,
    required Color surface,
    required Color surfaceHigh,
    required Color highlight,
    required Color gutter,
  }) {
    const scheme = ColorScheme.dark(
      primary: TokyoNight.blue,
      onPrimary: TokyoNight.nightBgDark,
      primaryContainer: TokyoNight.blue0,
      onPrimaryContainer: TokyoNight.fg,
      secondary: TokyoNight.magenta,
      onSecondary: TokyoNight.nightBgDark,
      tertiary: TokyoNight.green1,
      onTertiary: TokyoNight.nightBgDark,
      error: TokyoNight.red,
      onError: TokyoNight.nightBgDark,
      outline: TokyoNight.dark3,
      outlineVariant: TokyoNight.nightGutter,
    );

    final s = scheme.copyWith(
      surface: bg,
      onSurface: TokyoNight.fg,
      surfaceDim: bgDark,
      surfaceBright: surfaceHigh,
      surfaceContainerLowest: bgDark,
      surfaceContainerLow: surface,
      surfaceContainer: surface,
      surfaceContainerHigh: surfaceHigh,
      surfaceContainerHighest: highlight,
      onSurfaceVariant: TokyoNight.fgDark,
      outlineVariant: gutter,
      secondaryContainer: highlight,
      onSecondaryContainer: TokyoNight.fg,
      inverseSurface: TokyoNight.fg,
      onInverseSurface: bgDark,
    );

    return _common(s, scaffold: bg, hint: TokyoNight.comment);
  }

  static ThemeData day() {
    const scheme = ColorScheme.light(
      primary: TokyoNight.dayBlue,
      onPrimary: Color(0xFFFFFFFF),
      primaryContainer: Color(0xFFC4CBE5),
      onPrimaryContainer: Color(0xFF1B2440),
      secondary: TokyoNight.dayMagenta,
      onSecondary: Color(0xFFFFFFFF),
      tertiary: TokyoNight.dayCyan,
      onTertiary: Color(0xFFFFFFFF),
      error: TokyoNight.dayRed,
      onError: Color(0xFFFFFFFF),
      outline: TokyoNight.dayComment,
      outlineVariant: Color(0xFFB7BCCD),
    );

    final s = scheme.copyWith(
      surface: TokyoNight.dayBg,
      onSurface: Color(0xFF3760BF),
      surfaceDim: TokyoNight.daySurface,
      surfaceBright: Color(0xFFF2F3F7),
      surfaceContainerLowest: Color(0xFFF2F3F7),
      surfaceContainerLow: TokyoNight.dayCard,
      surfaceContainer: TokyoNight.dayCard,
      surfaceContainerHigh: TokyoNight.daySurface,
      surfaceContainerHighest: Color(0xFFC8CAD4),
      onSurfaceVariant: Color(0xFF6172B0),
      secondaryContainer: Color(0xFFD8D9E0),
      onSecondaryContainer: Color(0xFF3760BF),
    );

    return _common(s, scaffold: TokyoNight.dayBg, hint: TokyoNight.dayComment);
  }

  /// Shape, typography and component styling shared by every variant.
  static ThemeData _common(
    ColorScheme s, {
    required Color scaffold,
    required Color hint,
  }) {
    final base = ThemeData(useMaterial3: true, colorScheme: s);

    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      splashFactory: InkSparkle.splashFactory,
      textTheme: base.textTheme.apply(
        bodyColor: s.onSurface,
        displayColor: s.onSurface,
      ),
      appBarTheme: AppBarTheme(
        backgroundColor: scaffold,
        surfaceTintColor: Colors.transparent,
        foregroundColor: s.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          color: s.onSurface,
          fontSize: 20,
          fontWeight: FontWeight.w700,
          letterSpacing: -0.3,
        ),
      ),
      cardTheme: CardThemeData(
        color: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      dividerTheme: DividerThemeData(color: s.outlineVariant, thickness: 1, space: 1),
      chipTheme: ChipThemeData(
        backgroundColor: s.surfaceContainerLow,
        selectedColor: s.primary.withValues(alpha: 0.18),
        side: BorderSide(color: s.outlineVariant),
        labelStyle: TextStyle(color: s.onSurfaceVariant, fontWeight: FontWeight.w600, fontSize: 13),
        secondaryLabelStyle: TextStyle(color: s.primary, fontWeight: FontWeight.w700, fontSize: 13),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
        showCheckmark: false,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: s.surfaceContainerLow,
        hintStyle: TextStyle(color: hint),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: s.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide(color: s.primary, width: 2),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: s.primary,
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: s.onSurface,
          side: BorderSide(color: s.outlineVariant),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: s.primary,
        foregroundColor: s.onPrimary,
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: s.surfaceContainerLowest,
        surfaceTintColor: Colors.transparent,
        indicatorColor: s.primary.withValues(alpha: 0.16),
        elevation: 0,
        height: 68,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            size: 23,
            color: states.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant,
          ),
        ),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontSize: 11.5,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w700 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? s.primary : s.onSurfaceVariant,
          ),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        showDragHandle: true,
        dragHandleColor: s.outlineVariant,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: s.surfaceContainerLow,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: s.outlineVariant),
        ),
      ),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: s.surfaceContainerHighest,
        contentTextStyle: TextStyle(color: s.onSurface, fontWeight: FontWeight.w600),
        actionTextColor: s.primary,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(
        iconColor: s.onSurfaceVariant,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: s.primary,
        linearTrackColor: s.surfaceContainerHighest,
      ),
      sliderTheme: SliderThemeData(
        activeTrackColor: s.primary,
        inactiveTrackColor: s.surfaceContainerHighest,
        thumbColor: s.primary,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected) ? s.primary : s.outline,
        ),
        trackColor: WidgetStateProperty.resolveWith(
          (st) => st.contains(WidgetState.selected)
              ? s.primary.withValues(alpha: 0.35)
              : s.surfaceContainerHighest,
        ),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: s.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(8),
        ),
        textStyle: TextStyle(color: s.onSurface, fontSize: 12),
      ),
    );
  }
}
