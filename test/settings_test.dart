import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/screens/settings_screen.dart';
import 'package:qr_identity/ui/app_strings.dart';
import 'package:qr_identity/widgets/verify_steps.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('settings renders language, appearance, models, about',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    // Language section
    expect(find.text('ဘာသာစကား'), findsOneWidget);
    expect(find.byType(SegmentedButton<String>), findsOneWidget);
    // Appearance section
    expect(find.text('အပြင်အဆင်'), findsOneWidget);
    expect(find.byType(SegmentedButton<ThemeMode>), findsOneWidget);
    // Models section
    expect(find.textContaining('မျက်နှာမော်ဒယ်'), findsOneWidget);
    // About is below the fold — scroll to it.
    await tester.scrollUntilVisible(
      find.textContaining('eID Verify 0.9.0'),
      500,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.textContaining('eID Verify 0.9.0'), findsOneWidget);
  });

  testWidgets('language toggle switches between my and en',
      (WidgetTester tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(() => LanguageController.instance.setLang('my'));
    await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    // Default is Burmese — section header in Burmese.
    expect(find.text('ဘာသာစကား'), findsOneWidget);
    // Switch to English.
    await tester.tap(find.text('English'));
    await tester.pump();
    expect(find.text('LANGUAGE'), findsOneWidget);
  });

  testWidgets('step header marks progress 1-2-3', (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(
            home: Scaffold(
                body: VerifyStepsHeader(current: 2))));
    await tester.pump();
    expect(find.text('စကင်ဖတ်'), findsOneWidget);
    expect(find.text('မျက်နှာ'), findsOneWidget);
    expect(find.text('ကတ်'), findsOneWidget);
  });
}
