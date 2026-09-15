import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/screens/home_screen.dart';
import 'package:qr_identity/screens/scanner_screen.dart';
import 'package:qr_identity/ui/app_theme.dart';
import 'package:qr_identity/widgets/score_gauge.dart';
import 'package:qr_identity/widgets/verdict_chip.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('score gauge shows score and threshold', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ScoreGauge(score: 0.742, threshold: 0.40),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('0.742'), findsOneWidget);
    expect(find.textContaining('0.40'), findsOneWidget);
  });

  testWidgets('verdict chip renders label', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: VerdictChip(
            icon: Icons.check_circle,
            label: 'Match',
            color: Colors.green,
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Match'), findsOneWidget);
  });

  testWidgets('home screen shows branding and scan button', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: HomeScreen()),
    );
    await tester.pump();
    expect(find.text('eID စစ်ဆေးခြင်း'), findsOneWidget);
    expect(find.byIcon(Icons.qr_code_scanner_outlined), findsOneWidget);
    expect(find.byIcon(Icons.settings_outlined), findsOneWidget);
  });

  testWidgets('theme toggle switches controller mode', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => ThemeController.instance.value = ThemeMode.system);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const Scaffold(body: Text('x')),
      ),
    );
    await tester.pump();
    expect(ThemeController.instance.value, ThemeMode.system);
    await ThemeController.instance.setMode(ThemeMode.dark);
    await tester.pump();
    expect(ThemeController.instance.value, ThemeMode.dark);
    final stored =
        await SharedPreferences.getInstance().then((p) => p.getString('app_theme_mode'));
    expect(stored, 'dark');
  });

  testWidgets('dark theme builds scanner without overflow', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        themeMode: ThemeMode.dark,
        home: const ScannerScreen(),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
  });
}
