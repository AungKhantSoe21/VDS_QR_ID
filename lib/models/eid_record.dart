import 'dart:typed_data';

/// Decrypted eID identity record (inner CBOR payload).
///
/// Layout (server `lib/codec.js encodeEnroll`):
/// - v3: `CBOR([3, id, ts, name, idNumber, fmt, passportBytes, fingerprintBytes])`
/// - v2 legacy: `CBOR([2, id, ts, name, idNumber, passportBytes, fingerprintBytes])`, `fmt='jpeg'`
class EidRecord {
  const EidRecord({
    required this.version,
    required this.id,
    required this.timestamp,
    required this.name,
    required this.idNumber,
    required this.format,
    required this.passport,
    required this.fingerprint,
  });

  final int version;
  final String id;
  final String timestamp;
  final String name;
  final String idNumber;

  /// `'avif'` (current) or `'jpeg'`.
  final String format;
  final Uint8List passport;
  final Uint8List fingerprint;

  /// MIME matching server `toDataUrl()`: avif → image/avif, else image/jpeg.
  String get mime => format == 'avif' ? 'image/avif' : 'image/jpeg';
}
