import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/external_finger_reader.dart';

void main() {
  test('unimplemented reader reports missing hardware, never a verdict',
      () async {
    const reader = UnimplementedReader();
    try {
      await reader.capture();
      fail('must throw');
    } on ReaderNotConnected catch (e) {
      expect(e.detail, contains('OTG'));
    }
    try {
      await reader.match(
          FingerSample(Uint8List.fromList([1, 2, 3])), Uint8List(0));
      fail('must throw');
    } on ReaderNotConnected {
      // expected — no fabricated match
    }
  });
}
