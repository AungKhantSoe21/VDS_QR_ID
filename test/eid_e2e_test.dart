import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/config/eid_key.dart';
import 'package:qr_identity/services/eid_codec.dart';
import 'package:qr_identity/services/eid_crypto.dart';
import 'package:qr_identity/services/eid_parser.dart';

// Dedicated test key (never the server key): 32 bytes of 0x0b.
const _testKeyHex =
    '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b';

// 1x1 PNG bytes reused as fake passport/fingerprint thumbs.
const _tinyPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<Uint8List> _buildEnvelope() async {
  final crypto = EidCrypto(keyBytes: hexDecode(_testKeyHex));
  final img = base64.decode(_tinyPngB64);
  final payload = EidCodec.encodePayloadV3(
    id: 'uuid-test-1',
    ts: '2026-09-09T00:00:00Z',
    name: 'Test User',
    idNumber: 'T-001',
    fmt: 'jpeg',
    passport: Uint8List.fromList(img),
    fingerprint: Uint8List.fromList(img),
  );
  final enc = await crypto.encrypt(payload);
  return EidCodec.encodeEnvelope(
      version: 3, iv: enc.iv, tag: enc.tag, ct: enc.ct);
}

EidParser _parser() =>
    EidParser(crypto: EidCrypto(keyBytes: hexDecode(_testKeyHex)));

void main() {
  test('full offline pipeline decrypts to record', () async {
    final envelope = await _buildEnvelope();
    final rec = await _parser().parseEnvelopeBytes(envelope);
    expect(rec.version, 3);
    expect(rec.id, 'uuid-test-1');
    expect(rec.name, 'Test User');
    expect(rec.idNumber, 'T-001');
    expect(rec.mime, 'image/jpeg');
    expect(rec.passport, base64.decode(_tinyPngB64));
    expect(rec.fingerprint, base64.decode(_tinyPngB64));
  });

  test('qrText base64url round-trip (enroll parity)', () async {
    final envelope = await _buildEnvelope();
    final qrText = EidParser.envelopeToQrText(envelope);
    expect(qrText.contains('+'), false);
    expect(qrText.contains('/'), false);
    final rec = await _parser().parseQrTextB64Url(qrText);
    expect(rec.id, 'uuid-test-1');
  });

  test('tampered ciphertext fails with auth-failed', () async {
    final envelope = await _buildEnvelope();
    final tampered = Uint8List.fromList(envelope);
    tampered[tampered.length - 1] ^= 0x01;
    expect(() => _parser().parseEnvelopeBytes(tampered),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'auth-failed')));
  });

  test('wrong key fails with auth-failed', () async {
    final envelope = await _buildEnvelope();
    final wrong = EidParser(
        crypto: EidCrypto(keyBytes: Uint8List.fromList(List.filled(32, 1))));
    expect(() => wrong.parseEnvelopeBytes(envelope),
        throwsA(isA<FormatException>()
            .having((e) => e.message, 'message', 'auth-failed')));
  });

  test('missing key gives actionable error', () {
    expect(() => eidKeyBytes(overrideHex: ''),
        throwsA(isA<FormatException>().having((e) => e.message, 'message',
            contains('ENCRYPTION_KEY missing'))));
  });
}
