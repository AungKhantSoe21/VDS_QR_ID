import 'dart:typed_data';

import 'package:cbor/simple.dart';

import '../models/eid_record.dart';

/// CBOR envelope + payload codec (server `lib/codec.js` semantics).
///
/// - Envelope: `CBOR([VERSION, ivBytes, tagBytes, ctBytes])`, VERSION 3 (accept 2).
/// - Payload v3: `CBOR([3, id, ts, name, idNumber, fmt, passport, fingerprint])`
/// - Payload v2: `CBOR([2, id, ts, name, idNumber, passport, fingerprint])`, fmt implied jpeg.
class EidCodec {
  static const _decoder = CborSimpleDecoder();
  static const _encoder = CborSimpleEncoder();

  /// Decodes `envelopeBytes` → `(version, iv, tag, ct)`.
  static ({int version, Uint8List iv, Uint8List tag, Uint8List ct})
      decodeEnvelope(Uint8List envelopeBytes) {
    if (envelopeBytes.isEmpty) {
      throw const FormatException('malformed-envelope');
    }
    late Object? decoded;
    try {
      decoded = _decoder.convert(envelopeBytes);
    } catch (_) {
      throw const FormatException('malformed-envelope');
    }
    if (decoded is! List || decoded.length != 4) {
      throw const FormatException('malformed-envelope');
    }
    final v = _asInt(decoded[0]);
    final iv = _asBytes(decoded[1]);
    final tag = _asBytes(decoded[2]);
    final ct = _asBytes(decoded[3]);
    if ((v != 3 && v != 2) || iv.length != 12 || tag.length != 16 || ct.isEmpty) {
      throw const FormatException('malformed-envelope');
    }
    return (version: v, iv: iv, tag: tag, ct: ct);
  }

  /// Decodes GCM plaintext → [EidRecord].
  static EidRecord decodePayload(Uint8List plain) {
    late Object? decoded;
    try {
      decoded = _decoder.convert(plain);
    } catch (_) {
      throw const FormatException('malformed-envelope');
    }
    if (decoded is! List) throw const FormatException('malformed-envelope');
    if (decoded.isEmpty) throw const FormatException('malformed-envelope');
    final v = _asInt(decoded[0]);
    if (v == 3) {
      if (decoded.length != 8) throw const FormatException('malformed-envelope');
      return EidRecord(
        version: v,
        id: _asString(decoded[1]),
        timestamp: _asString(decoded[2]),
        name: _asString(decoded[3]),
        idNumber: _asString(decoded[4]),
        format: _asString(decoded[5]),
        passport: _asBytes(decoded[6]),
        fingerprint: _asBytes(decoded[7]),
      );
    }
    if (v == 2) {
      if (decoded.length != 7) throw const FormatException('malformed-envelope');
      return EidRecord(
        version: v,
        id: _asString(decoded[1]),
        timestamp: _asString(decoded[2]),
        name: _asString(decoded[3]),
        idNumber: _asString(decoded[4]),
        format: 'jpeg',
        passport: _asBytes(decoded[5]),
        fingerprint: _asBytes(decoded[6]),
      );
    }
    throw const FormatException('unsupported-version');
  }

  /// Encoders for tests/tools (mirror `packQrEnvelopeBytes` / `encodeEnroll`).
  static Uint8List encodeEnvelope({
    required int version,
    required Uint8List iv,
    required Uint8List tag,
    required Uint8List ct,
  }) =>
      Uint8List.fromList(_encoder.convert([version, iv, tag, ct]));

  static Uint8List encodePayloadV3({
    required String id,
    required String ts,
    required String name,
    required String idNumber,
    required String fmt,
    required Uint8List passport,
    required Uint8List fingerprint,
  }) =>
      Uint8List.fromList(
          _encoder.convert([3, id, ts, name, idNumber, fmt, passport, fingerprint]));

  static int _asInt(Object? v) {
    if (v is int) return v;
    throw const FormatException('malformed-envelope');
  }

  static String _asString(Object? v) {
    if (v is String) return v;
    throw const FormatException('malformed-envelope');
  }

  static Uint8List _asBytes(Object? v) {
    if (v is Uint8List) return v;
    if (v is List<int>) return Uint8List.fromList(v);
    if (v is List) {
      return Uint8List.fromList(v.map((e) {
        if (e is int) return e;
        throw const FormatException('malformed-envelope');
      }).toList());
    }
    throw const FormatException('malformed-envelope');
  }
}
