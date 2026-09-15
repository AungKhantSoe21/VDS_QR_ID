import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// eID Verify design system — soft temple-green identity sampled from
/// `assets/card/pattern_front.png` (ink hue ~120° deepened for contrast)
/// with emblem gold accents.
///
/// - [seed] `#4C8056`: primary interactive green.
/// - [gold] `#C9A65C`: tertiary accent (checks, active step, highlights).
/// - [deep] `#243D2B`: splash/hero fields.
/// - [paleSage] `#E9F1EA`: surface tints, splash text.
///
/// No custom fonts and no new packages: Burmese renders via OS system
/// fonts, everything else is SDK Material 3. [themeMode] is app-global
/// (loaded at splash, toggled in Settings, persisted).
class AppTheme {
  static const seed = Color(0xFF4C8056);
  static const gold = Color(0xFFC9A65C);
  static const deep = Color(0xFF243D2B);
  static const paleSage = Color(0xFFE9F1EA);

  static const double radiusCard = 20;
  static const double radiusSheet = 28;
  static const double radiusButton = 16;
  static const EdgeInsets screenPadding = EdgeInsets.all(20);

  /// Shared AppBar gradient — used by every AppBar in the app.
  static const appBarGradient = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [deep, seed],
  );

  static ThemeData light() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.light,
    ).copyWith(tertiary: gold);
    return _base(scheme);
  }

  static ThemeData dark() {
    final scheme = ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ).copyWith(
      tertiary: const Color(0xFFDDBB77),
      surfaceContainerHighest: const Color(0xFF1A2B1F),
    );
    return _base(scheme);
  }

  static ThemeData _base(ColorScheme scheme) => ThemeData(
        colorScheme: scheme,
        useMaterial3: true,
        scaffoldBackgroundColor: scheme.surface,
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          foregroundColor: Colors.white,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w800,
            color: Colors.white,
          ),
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusCard),
            side: BorderSide(color: scheme.outlineVariant),
          ),
          clipBehavior: Clip.antiAlias,
        ),
        bottomSheetTheme: const BottomSheetThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(
                top: Radius.circular(radiusSheet)),
          ),
          showDragHandle: true,
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton),
            ),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size(48, 52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusButton),
            ),
            textStyle: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.w700),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(radiusButton),
          ),
          filled: true,
        ),
        sliderTheme: SliderThemeData(
          activeTrackColor: scheme.primary,
          inactiveTrackColor: scheme.surfaceContainerHighest,
          thumbColor: gold,
          overlayColor: gold.withValues(alpha: 0.2),
        ),
        snackBarTheme: const SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.all(Radius.circular(14)),
          ),
        ),
        dialogTheme: DialogThemeData(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(radiusSheet),
          ),
        ),
        dividerTheme: const DividerThemeData(space: 1, thickness: 1),
      );
}

/// App-global theme mode: loaded at splash, toggled in Settings,
/// persisted in SharedPreferences.
class ThemeController extends ValueNotifier<ThemeMode> {
  ThemeController() : super(ThemeMode.system);

  static const prefsKey = 'app_theme_mode';
  static final ThemeController instance = ThemeController();

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      value = _fromString(prefs.getString(prefsKey));
    } catch (_) {
      // Keep system default.
    }
  }

  Future<void> setMode(ThemeMode mode) async {
    value = mode;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(prefsKey, _toString(mode));
    } catch (_) {}
  }

  static ThemeMode _fromString(String? s) => switch (s) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };

  static String _toString(ThemeMode m) => switch (m) {
        ThemeMode.light => 'light',
        ThemeMode.dark => 'dark',
        ThemeMode.system => 'system',
      };
}
