import 'dart:typed_data';

import '../services/mosip.dart';
import 'eid_record.dart';

/// Unified card content from EITHER QR format.
///
/// - MOSIP Claim 169 (`verifyQrTextOffline`): demographics + face hash
///   for auto-matching (+ optional embedded portrait, ignored here).
/// - Legacy envelope v2/v3 (`EidParser`, see
///   `image_encryption_backend.md`): demographics only.
///
/// Neither format carries a displayable holder photo (the QR holds a
/// face *pattern* for verification, not an image), so the card shows
/// data only — no portrait box, no selfie substitute.
class CardData {
  const CardData({
    required this.name,
    required this.uid,
    required this.nationalReg,
    required this.dob,
    required this.issuer,
    required this.exp,
    required this.portrait,
    required this.portraitMime,
    required this.qrText,
    required this.qrMode,
    required this.faceHash,
    required this.biometricNote,
    required this.credential,
  });

  /// Display name ('' when absent — UI shows '—').
  final String name;

  /// `UID No.` value: record/credential id.
  final String uid;

  /// National-reg number (legacy `idNumber` only; '' otherwise → '—').
  final String nationalReg;

  /// `YYYYMMDD` or '' when the format carries none (legacy).
  final String dob;

  final String issuer;
  final int? exp;

  /// QR portrait bytes for the visual-confirm step (legacy photo QRs).
  /// The ID card itself shows no photo. Null when the QR holds none.
  final Uint8List? portrait;

  /// MIME for [portrait] (`image/jpeg` fallback).
  final String portraitMime;

  /// QR payload re-rendered on the card back: the exact alphanumeric
  /// text for MOSIP; base64url(envelopeBytes) transport form for legacy
  /// (functionally equivalent — decodes via the same parser).
  final String qrText;

  /// `mosip-encrypted` | `mosip-id-free` | `legacy-v3` | `legacy-v2`.
  final String qrMode;

  /// Face hash for auto-matching, or null (legacy) → visual confirm.
  final Uint8List? faceHash;

  /// One-line biometric reference for the card back
  /// (`face 65B · FMR 222B` | `face photo 1.8KB · finger photo 1.1KB`).
  final String biometricNote;

  /// Source MOSIP credential (null for legacy). Passed to the matcher.
  final MosipCredential? credential;

  factory CardData.fromMosip(MosipCredential c, String qrText) {
    var mime = 'image/jpeg';
    final p = c.portrait;
    if (p != null && p.length >= 8 && p[4] == 0x66) {
      mime = 'image/png';
    }
    return CardData(
      name: c.name,
      uid: c.id ?? '—',
      nationalReg: '',
      dob: c.dob,
      issuer: c.iss,
      exp: c.exp,
      portrait: p,
      portraitMime: mime,
      qrText: qrText,
      qrMode: c.qrMode == 'encrypted' ? 'mosip-encrypted' : 'mosip-id-free',
      faceHash: c.faceHash,
      biometricNote:
          'face ${c.faceHash.length}B · FMR ${c.fmr.length}B',
      credential: c,
    );
  }

  factory CardData.fromLegacy(EidRecord r, String qrText) {
    String kb(Uint8List b) => '${(b.length / 1024).toStringAsFixed(1)}KB';
    return CardData(
      name: r.name,
      uid: r.id,
      nationalReg: r.idNumber,
      dob: '',
      issuer: '—',
      exp: null,
      portrait: r.passport,
      portraitMime: r.mime,
      qrText: qrText,
      qrMode: 'legacy-v${r.version}',
      faceHash: null,
      biometricNote:
          'face photo ${kb(r.passport)} · finger photo ${kb(r.fingerprint)}',
      credential: null,
    );
  }
}
