import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/widgets/identity_image.dart';

/// Minimal `ftypavif` header: size(4) + 'ftyp' + 'avif'.
Uint8List avifMagic() => Uint8List.fromList(
    [0, 0, 0, 32, 0x66, 0x74, 0x79, 0x70, 0x61, 0x76, 0x69, 0x66]);

Future<void> pumpImage(
        WidgetTester tester, Uint8List bytes, String mime) async {
  await tester.pumpWidget(MaterialApp(
    home: Scaffold(
        body: IdentityImage(bytes: bytes, mime: mime, label: 'passport')),
  ));
  await tester.pump();
}

void main() {
  // Routing only (native AVIF decode isn't available under flutter_test;
  // decode failures surface via errorBuilder on-device).
  testWidgets('avif mime routes to AvifImage', (tester) async {
    await pumpImage(tester, avifMagic(), 'image/avif');
    expect(find.byType(AvifImage), findsOneWidget);
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('avif bytes sniffed even with jpeg mime', (tester) async {
    await pumpImage(tester, avifMagic(), 'image/jpeg');
    expect(find.byType(AvifImage), findsOneWidget);
  });

  testWidgets('jpeg bytes route to framework Image', (tester) async {
    final png = Uint8List.fromList(
        [105, 86, 66, 82, ...List.filled(20, 0)]); // 'IVBR' ≠ 'ftyp'
    await pumpImage(tester, png, 'image/jpeg');
    expect(find.byType(Image), findsOneWidget);
    expect(find.byType(AvifImage), findsNothing);
  });
}
