import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/main.dart';
import 'package:qr_identity/screens/home_screen.dart';
import 'package:qr_identity/screens/splash_screen.dart';

void main() {
  testWidgets('App boots splash, then home screen', (WidgetTester tester) async {
    await tester.pumpWidget(const QrIdentityApp());
    expect(find.byType(SplashScreen), findsOneWidget);
    // Real init + min hold + fade, then the home screen takes over.
    for (var i = 0;
        i < 20 && find.byType(HomeScreen).evaluate().isEmpty;
        i++) {
      await tester.pump(const Duration(milliseconds: 500));
    }
    expect(find.byType(HomeScreen), findsOneWidget);
    expect(find.byType(SplashScreen), findsNothing);
  });
}
