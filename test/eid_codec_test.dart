import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/eid_codec.dart';

void main() {
  final iv = Uint8List.fromList(List.generate(12, (i) => i));
  final tag = Uint8List.fromList(List.generate(16, (i) => 100 + i));
  final ct = Uint8List.fromList([1, 2, 3, 4, 5]);

  test('envelope round-trip v3', () {
    final bytes = EidCodec.encodeEnvelope(version: 3, iv: iv, tag: tag, ct: ct);
    final env = EidCodec.decodeEnvelope(bytes);
    expect(env.version, 3);
    expect(env.iv, iv);
    expect(env.tag, tag);
    expect(env.ct, ct);
  });

  test('payload round-trip v3', () {
    final passport = Uint8List.fromList([10, 20, 30]);
    final fp = Uint8List.fromList([40, 50]);
    final bytes = EidCodec.encodePayloadV3(
      id: 'uuid-1',
      ts: '2026-01-01T00:00:00Z',
      name: 'Ada',
      idNumber: 'ID-9',
      fmt: 'avif',
      passport: passport,
      fingerprint: fp,
    );
    final rec = EidCodec.decodePayload(bytes);
    expect(rec.version, 3);
    expect(rec.id, 'uuid-1');
    expect(rec.name, 'Ada');
    expect(rec.idNumber, 'ID-9');
    expect(rec.format, 'avif');
    expect(rec.mime, 'image/avif');
    expect(rec.passport, passport);
    expect(rec.fingerprint, fp);
  });

  test('empty input is malformed-envelope', () {
    expect(() => EidCodec.decodeEnvelope(Uint8List(0)),
        throwsA(isA<FormatException>().having(
            (e) => e.message, 'message', 'malformed-envelope')));
  });

  test('garbage bytes are malformed-envelope', () {
    expect(() => EidCodec.decodeEnvelope(Uint8List.fromList([1, 2, 3])),
        throwsFormatException);
  });

  test('bad iv length is malformed-envelope', () {
    final bytes = EidCodec.encodeEnvelope(
        version: 3,
        iv: Uint8List.fromList([1, 2]),
        tag: tag,
        ct: ct);
    expect(() => EidCodec.decodeEnvelope(bytes), throwsFormatException);
  });
}
