import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/main.dart';

void main() {
  testWidgets('App launches scanner screen', (WidgetTester tester) async {
    await tester.pumpWidget(const QrIdentityApp());
    await tester.pump();
    // AppBar title shows with or without EID_KEY configured.
    expect(find.text('eID Verify'), findsOneWidget);
  });
}
