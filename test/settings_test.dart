import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/screens/settings_screen.dart';
import 'package:qr_identity/widgets/verify_steps.dart';

void main() {
  testWidgets('settings renders threshold, models, about sections',
      (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: SettingsScreen()));
    await tester.pump();
    expect(find.text('FACE MATCH'), findsOneWidget);
    expect(find.text('FACE MODELS (ON-DEVICE)'), findsOneWidget);
    expect(find.text('ABOUT'), findsOneWidget);
    expect(find.textContaining('eID Verify 0.9.0'), findsOneWidget);
  });

  testWidgets('step header marks progress 1-2-3', (WidgetTester tester) async {
    await tester.pumpWidget(
        const MaterialApp(
            home: Scaffold(
                body: VerifyStepsHeader(current: 2))));
    await tester.pump();
    expect(find.text('Scan'), findsOneWidget);
    expect(find.text('Face'), findsOneWidget);
    expect(find.text('Card'), findsOneWidget);
  });
}
