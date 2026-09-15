import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/eid_key.dart';
import '../config/env_parse.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import 'face_matcher.dart';
import 'face_model_pack.dart';

/// Cold-start stages, in order. Reported to the splash screen so the
/// "getting in" progress is backed by real work — never a fake timer.
enum StartupStage { config, preferences, models, done }

/// Outcome of [AppStartup.run]. Every step is failure-tolerant (mirrors
/// the old `main()`/`ScannerScreen` behavior): a missing `.env`, broken
/// prefs, or unverified model cache never blocks entering the app.
class StartupSummary {
  const StartupSummary({
    required this.keyLoaded,
    required this.modelsReady,
  });

  /// True when `.env` supplied a usable ENCRYPTION_KEY.
  final bool keyLoaded;

  /// True when the bundled face models are cached and hash-verified.
  final bool modelsReady;
}

/// Testable cold-start orchestration.
///
/// Default steps are the real implementations; tests inject fakes.
/// Progress is reported per stage as 0.0–1.0 overall.
class AppStartup {
  AppStartup({
    Future<void> Function()? loadConfig,
    Future<void> Function()? loadPreferences,
    Future<bool> Function()? checkModels,
  }) {
    _loadConfig = loadConfig ?? _defaultLoadConfig;
    _loadPreferences = loadPreferences ?? _defaultLoadPreferences;
    _checkModels = checkModels ?? _defaultCheckModels;
  }

  late final Future<void> Function() _loadConfig;
  late final Future<void> Function() _loadPreferences;
  late final Future<bool> Function() _checkModels;

  bool _keyOk = false;

  /// Moved out of `main()` so the splash can show it as stage 1.
  /// Missing/unreadable `.env` is tolerated — the scanner reports the
  /// config error at scan time.
  Future<void> _defaultLoadConfig() async {
    _keyOk = false;
    try {
      final raw = await rootBundle.loadString('.env');
      EidKeyConfig.setEnvFileHex(parseEnv(raw)['ENCRYPTION_KEY']);
      // Consider the key loaded only if it parses (same rule as scans).
      eidKeyBytes();
      _keyOk = true;
    } catch (_) {
      // No .env asset — key resolution reports the problem at scan time.
    }
  }

  /// Applies persisted prefs: face-match threshold + theme mode + language.
  Future<void> _defaultLoadPreferences() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(FaceMatcher.thresholdPrefsKey);
      if (saved != null && saved > 0 && saved < 1) {
        FaceMatcher.hashThreshold = saved;
      }
    } catch (_) {
      // Storage unavailable — keep the default.
    }
    await ThemeController.instance.load();
    await LanguageController.instance.load();
  }

  /// Hash-verifies the model cache. Check only — setup happens later
  /// at the face step, never on the splash (no network here).
  Future<bool> _defaultCheckModels() async {
    try {
      final pack = await FaceModelPack.system();
      final ready = await pack.isReady();
      return ready;
    } catch (_) {
      return false;
    }
  }

  Future<StartupSummary> run({
    void Function(StartupStage stage, double progress)? onProgress,
  }) async {
    void report(StartupStage stage, double progress) =>
        onProgress?.call(stage, progress);
    report(StartupStage.config, 0.0);
    try {
      await _loadConfig();
    } catch (_) {}
    final keyLoaded = _keyOk;
    report(StartupStage.preferences, 0.33);
    try {
      await _loadPreferences();
    } catch (_) {}
    report(StartupStage.models, 0.66);
    var modelsReady = false;
    try {
      modelsReady = await _checkModels();
    } catch (_) {}
    report(StartupStage.done, 1.0);
    return StartupSummary(keyLoaded: keyLoaded, modelsReady: modelsReady);
  }
}
