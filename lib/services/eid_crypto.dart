import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

import '../config/eid_key.dart';

/// AES-256-GCM for the eID envelope (server `lib/crypto.js` semantics:
/// `cipher.getAuthTag()` / `decipher.setAuthTag(tag)`, no AAD).
class EidCrypto {
  EidCrypto({Uint8List? keyBytes})
      : _keyBytes = keyBytes ?? eidKeyBytes();

  final Uint8List _keyBytes;
  final AesGcm _algo = AesGcm.with256bits();

  /// Decrypts one envelope: `plaintext = AES_GCM_DECRYPT(key, iv, ct, tag)`.
  Future<Uint8List> decrypt({
    required Uint8List iv,
    required Uint8List tag,
    required Uint8List ciphertext,
  }) async {
    if (_keyBytes.length != 32) {
      throw const FormatException('EID key must be 32 bytes (AES-256).');
    }
    if (iv.length != 12) throw const FormatException('malformed-envelope');
    if (tag.length != 16) throw const FormatException('malformed-envelope');
    final box = SecretBox(ciphertext, nonce: iv, mac: Mac(tag));
    try {
      final plain =
          await _algo.decrypt(box, secretKey: SecretKey(_keyBytes));
      return Uint8List.fromList(plain);
    } on SecretBoxAuthenticationError {
      throw const FormatException('auth-failed');
    }
  }

  /// Encrypt helper for tests/tools (Node `cipher.getAuthTag()` layout).
  Future<({Uint8List iv, Uint8List tag, Uint8List ct})> encrypt(
    List<int> plain, {
    List<int>? nonce,
  }) async {
    final box = await _algo.encrypt(
      plain,
      secretKey: SecretKey(_keyBytes),
      nonce: nonce,
    );
    return (
      iv: Uint8List.fromList(box.nonce),
      tag: Uint8List.fromList(box.mac.bytes),
      ct: Uint8List.fromList(box.cipherText),
    );
  }
}
