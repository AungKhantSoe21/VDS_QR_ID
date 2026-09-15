import 'dart:convert';
import 'dart:typed_data';

import '../models/eid_record.dart';
import 'eid_codec.dart';
import 'eid_crypto.dart';

/// Full offline pipeline (guide §1):
///
/// `envelopeBytes → CBOR → {iv,tag,ct} → AES-GCM → CBOR → EidRecord`.
class EidParser {
  EidParser({EidCrypto? crypto}) : _crypto = crypto ?? EidCrypto();

  final EidCrypto _crypto;

  /// Primary entry: raw QR bytes from the byte-aware scanner.
  Future<EidRecord> parseEnvelopeBytes(Uint8List envelopeBytes) async {
    if (envelopeBytes.isEmpty) {
      throw const FormatException('malformed-envelope');
    }
    final env = EidCodec.decodeEnvelope(envelopeBytes);
    final plain =
        await _crypto.decrypt(iv: env.iv, tag: env.tag, ciphertext: env.ct);
    return EidCodec.decodePayload(plain);
  }

  /// Debug/test entry: `qrText = base64url(envelopeBytes)` (guide §2,
  /// same as `qrEnvelopeB64url` in the enroll response). Accepts unpadded
  /// base64url; standard base64 tolerated.
  Future<EidRecord> parseQrTextB64Url(String qrText) async {
    final t = qrText.trim();
    if (t.isEmpty) throw const FormatException('malformed-envelope');
    late Uint8List bytes;
    try {
      final normalized = t.replaceAll('-', '+').replaceAll('_', '/');
      final padded = normalized + '=' * ((4 - normalized.length % 4) % 4);
      bytes = Uint8List.fromList(base64.decode(padded));
    } catch (_) {
      throw const FormatException('malformed-envelope');
    }
    return parseEnvelopeBytes(bytes);
  }

  /// Encodes raw envelope bytes as `qrText` for `POST /api/scan|verify` (guide §4).
  static String envelopeToQrText(Uint8List envelopeBytes) =>
      base64Url.encode(envelopeBytes).replaceAll('=', '');
}
