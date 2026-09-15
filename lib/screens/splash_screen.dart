import 'dart:async';

import 'package:flutter/material.dart';

import '../services/app_startup.dart';
import '../ui/app_strings.dart';
import 'home_screen.dart';

/// Cold-start splash: brand gradient + emblem + staged "getting in"
/// progress backed by real init work ([AppStartup]).
///
/// Stages: configuration (.env key) → preferences (threshold) → face-model
/// cache check (never downloads — setup stays at the face step). Holds a
/// minimum beat so the branding reads, then fades to [ScannerScreen].
/// Every stage is failure-tolerant; navigation is guaranteed by timeout.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key, this.startup});

  /// Injected for tests; production uses the real [AppStartup].
  final AppStartup? startup;

  /// Minimum visible time so the branding reads (does not delay init).
  static const minHold = Duration(milliseconds: 1200);

  /// Navigation always wins, even if init hangs.
  static const initTimeout = Duration(seconds: 5);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  StartupStage _stage = StartupStage.config;
  double _progress = 0.0;

  @override
  void initState() {
    super.initState();
    _boot();
  }

  Future<void> _boot() async {
    final started = DateTime.now();
    final startup = widget.startup ?? AppStartup();
    try {
      await startup
          .run(
            onProgress: (stage, progress) {
              if (!mounted) return;
              setState(() {
                _stage = stage;
                _progress = progress;
              });
            },
          )
          .timeout(SplashScreen.initTimeout);
    } catch (_) {
      // Init failed or timed out — enter anyway (screens tolerate it).
    }
    final elapsed = DateTime.now().difference(started);
    if (elapsed < SplashScreen.minHold) {
      await Future<void>.delayed(SplashScreen.minHold - elapsed);
    }
    if (!mounted) return;
    await Navigator.of(context).pushReplacement(
      PageRouteBuilder(
        transitionDuration: const Duration(milliseconds: 450),
        pageBuilder: (_, _, _) => const HomeScreen(),
        transitionsBuilder: (_, animation, _, child) => FadeTransition(opacity: animation, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF243D2B), Color(0xFF4C8056)]),
        ),
        child: Stack(
          children: [
            // Gold halo behind the emblem.
            const Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(center: Alignment(0.0, -0.35), radius: 0.55, colors: [Color(0x40C9A65C), Color(0x00C9A65C)]),
                ),
              ),
            ),
            SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const Spacer(flex: 3),
                    Image.asset('assets/card/emblem.png', width: 120, height: 120, errorBuilder: (_, _, _) => const Icon(Icons.verified_user, size: 96, color: Color(0xFFC9A65C))),
                    const SizedBox(height: 20),
                    Text(
                      S.appName,
                      style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800, color: Colors.white, letterSpacing: 0.5),
                    ),
                    const Spacer(flex: 2),
                    _StageList(stage: _stage),
                    const SizedBox(height: 16),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: _progress.clamp(0.0, 1.0),
                        backgroundColor: Colors.white.withValues(alpha: 0.15),
                        valueColor: const AlwaysStoppedAnimation(Color(0xFFC9A65C)),
                        minHeight: 4,
                      ),
                    ),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StageList extends StatelessWidget {
  const _StageList({required this.stage});

  final StartupStage stage;

  static const _rows = [(StartupStage.config, 'Configuration', 'ပြင်ဆင်မှု'), (StartupStage.preferences, 'Preferences', 'ရွေးချယ်မှုများ'), (StartupStage.models, 'Face models', 'မျက်နှာမော်ဒယ်များ')];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      decoration: BoxDecoration(color: const Color(0xFFE9F1EA).withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final (s, en, my) in _rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 5),
              child: Row(
                children: [
                  _StageIcon(state: _stateFor(s)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      en,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.white),
                    ),
                  ),
                  Text(my, style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.75))),
                ],
              ),
            ),
        ],
      ),
    );
  }

  _RowState _stateFor(StartupStage s) {
    final order = StartupStage.values;
    if (stage == StartupStage.done || order.indexOf(s) < order.indexOf(stage)) {
      return _RowState.done;
    }
    if (s == stage) return _RowState.active;
    return _RowState.pending;
  }
}

enum _RowState { pending, active, done }

class _StageIcon extends StatelessWidget {
  const _StageIcon({required this.state});

  final _RowState state;

  @override
  Widget build(BuildContext context) {
    switch (state) {
      case _RowState.done:
        return const Icon(Icons.check_circle, size: 22, color: Color(0xFFC9A65C));
      case _RowState.active:
        return const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, valueColor: AlwaysStoppedAnimation(Color(0xFFC9A65C))));
      case _RowState.pending:
        return Icon(Icons.circle_outlined, size: 22, color: Colors.white.withValues(alpha: 0.4));
    }
  }
}
