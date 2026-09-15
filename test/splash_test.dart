import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/screens/home_screen.dart';
import 'package:qr_identity/screens/splash_screen.dart';
import 'package:qr_identity/services/app_startup.dart';

AppStartup _fake({Duration delay = Duration.zero}) => AppStartup(
      loadConfig: () async {
        await Future<void>.delayed(delay);
      },
      loadPreferences: () async {},
      checkModels: () async => true,
    );

void main() {
  testWidgets('splash shows branding, stages, and progress', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SplashScreen(startup: _fake())),
    );
    expect(find.text('eID စစ်ဆေးခြင်း'), findsOneWidget);
    expect(find.text('Configuration'), findsOneWidget);
    expect(find.text('Face models'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    // Flush the min-hold timer (no pumpAndSettle: the home screen
    // has a repeating animation by design).
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeScreen), findsOneWidget);
  });

  testWidgets('splash fades to the home screen after init', (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: SplashScreen(startup: _fake())),
    );
    await tester.pump(const Duration(milliseconds: 1300));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });

  testWidgets('splash still enters when init hangs (timeout)', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
          home: SplashScreen(
              startup: AppStartup(
        loadConfig: () async {
          await Future<void>.delayed(const Duration(minutes: 1));
        },
        loadPreferences: () async {},
        checkModels: () async => false,
      ))),
    );
    await tester.pump(const Duration(seconds: 6));
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(HomeScreen), findsOneWidget);
    await tester.pump(const Duration(minutes: 2));
    await tester.pump(const Duration(milliseconds: 500));
  });
}
