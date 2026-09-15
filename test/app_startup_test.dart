import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/app_startup.dart';

void main() {
  test('run reports stages in order with real progress', () async {
    final seen = <StartupStage>[];
    var done = false;
    final summary = await AppStartup(
      loadConfig: () async {},
      loadPreferences: () async {},
      checkModels: () async {
        done = true;
        return true;
      },
    ).run(onProgress: (stage, progress) {
      seen.add(stage);
      expect(progress, inInclusiveRange(0.0, 1.0));
    });
    expect(seen, [
      StartupStage.config,
      StartupStage.preferences,
      StartupStage.models,
      StartupStage.done,
    ]);
    expect(done, isTrue);
    expect(summary.modelsReady, isTrue);
    // Default key check runs against the test bundle (no .env asset).
    expect(summary.keyLoaded, isFalse);
  });

  test('run tolerates failing steps and still completes', () async {
    final summary = await AppStartup(
      loadConfig: () async => throw StateError('no env'),
      loadPreferences: () async => throw StateError('no prefs'),
      checkModels: () async => throw StateError('no models'),
    ).run();
    expect(summary.keyLoaded, isFalse);
    expect(summary.modelsReady, isFalse);
  });

  test('keyLoaded reflects injected config outcome only', () async {
    var flag = false;
    final ok = await AppStartup(
      loadConfig: () async => flag = true,
      loadPreferences: () async {},
      checkModels: () async => false,
    ).run();
    expect(flag, isTrue);
    // Injected config does not touch the real key state.
    expect(ok.keyLoaded, isFalse);
  });
}
