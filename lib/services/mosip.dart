import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cbor/cbor.dart';
import 'package:cryptography/cryptography.dart';

import '../config/eid_key.dart';
import '../config/issuer.dart';

/// Fully-offline MOSIP Claim 169 QR verification — Dart port of the
/// backend `lib/mosip.js` (SOURCE OF TRUTH for the QR format, agent.md §4).
///
/// No network: `Base45 → CBOR → (COSE_Encrypt0 decrypt) → zlib.inflate →
/// COSE_Sign1 EdDSA verify → expiry → identity`.
///
/// Two variants, routed by structure (never by trial order):
/// - encrypted: `Tag(61)` CWT → AES-256-GCM (`ENCRYPTION_KEY` as CEK) →
///   inflate → `Tag(18)` Sign1. `kid` must match [IssuerPin.kid].
/// - id-free: raw deflate → `Tag(18)` Sign1 verified with [IssuerPin]
///   public key; identity must NOT contain key `1:id`.
///
/// `reason` strings match the backend exactly: `malformed-qr|unknown-key|
/// expired|not-yet-valid|unsupported-legacy-qr|auth-failed`. Thrown as
/// [FormatException] messages (same convention as the rest of the app).
class MosipCredential {
  const MosipCredential({
    required this.qrMode,
    required this.iss,
    required this.exp,
    required this.nbf,
    required this.iat,
    required this.id,
    required this.name,
    required this.dob,
    required this.faceHash,
    required this.fmr,
    required this.fingerprints,
    required this.portrait,
    required this.portraitInfo,
  });

  /// `'encrypted'` or `'id-free'`.
  final String qrMode;
  final String iss;
  final int? exp;
  final int? nbf;
  final int? iat;

  /// Record id, or `null` for id-free credentials.
  final String? id;
  final String name;

  /// `YYYYMMDD`.
  final String dob;

  /// Versioned compact face template: `132B 0x02…` or `68B 0x03…`.
  final Uint8List faceHash;

  /// Primary ISO 19794-2 FMR bytes (key 50, or first available).
  final Uint8List fmr;

  /// Fingerprints keyed by MOSIP claim key (50=right thumb, 55=left thumb).
  final Map<int, Uint8List> fingerprints;

  /// Renderable portrait (JPEG/PNG) found anywhere in the identity map.
  final Uint8List? portrait;

  /// Describes ANY image-like find (even non-renderable JP2/BDB), or null.
  final PortraitInfo? portraitInfo;

  String get faceFormat {
    if (faceHash.length == 132 && faceHash[0] == 0x02) {
      return 'arcface-projected-int8';
    }
    if (faceHash.length == 68 && faceHash[0] == 0x03) {
      return 'arcface-projected-int8-v3';
    }
    return 'unknown';
  }
}

// ---------------------------------------------------------------- Base45 (DGC variant, port of mosip.js)

const _b45 = '0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ \$%*+-./:';

String base45Encode(Uint8List buf) {
  final out = StringBuffer();
  for (var i = 0; i < buf.length; i += 2) {
    if (i + 1 < buf.length) {
      final x = (buf[i] << 8) + buf[i + 1];
      out.write(_b45[x % 45]);
      out.write(_b45[(x ~/ 45) % 45]);
      out.write(_b45[x ~/ (45 * 45)]);
    } else {
      final x = buf[i];
      out.write(_b45[x % 45]);
      out.write(_b45[x ~/ 45]);
    }
  }
  return out.toString();
}

Uint8List base45Decode(String str) {
  final vals = <int>[];
  for (var i = 0; i < str.length; i++) {
    final v = _b45.indexOf(str[i]);
    if (v == -1) throw const FormatException('malformed-qr');
    vals.add(v);
  }
  final bytes = <int>[];
  var i = 0;
  while (i < vals.length) {
    final remaining = vals.length - i;
    if (remaining >= 3) {
      final x = vals[i] + vals[i + 1] * 45 + vals[i + 2] * 45 * 45;
      if (x > 0xffff) throw const FormatException('malformed-qr');
      bytes.add(x >> 8);
      bytes.add(x & 0xff);
      i += 3;
    } else if (remaining == 2) {
      final x = vals[i] + vals[i + 1] * 45;
      if (x > 0xff) throw const FormatException('malformed-qr');
      bytes.add(x);
      i += 2;
    } else {
      throw const FormatException('malformed-qr');
    }
  }
  return Uint8List.fromList(bytes);
}

// ---------------------------------------------------------------- CBOR helpers (tagged API — tags carry 61/18/16)

CborValue _decodeCbor(Uint8List bytes) {
  try {
    return cbor.decode(bytes);
  } catch (_) {
    throw const FormatException('malformed-qr');
  }
}

List<int> _encodeCbor(CborValue v) => cbor.encode(v);

CborList _asList(CborValue v) {
  if (v is CborList) return v;
  throw const FormatException('malformed-qr');
}

CborMap _asMap(CborValue v) {
  if (v is CborMap) return v;
  throw const FormatException('malformed-qr');
}

Uint8List _asBytes(CborValue? v) {
  if (v is CborBytes) return Uint8List.fromList(v.bytes);
  throw const FormatException('malformed-qr');
}

int? _optInt(CborValue? v) => v is CborInt ? v.toInt() : null;

// ---------------------------------------------------------------- COSE (RFC 8152, port of mosip.js)

const _tagCwt = 61;
const _tagSign1 = 18;
const _algEddsa = -8;
const _algA256gcm = 3;
const _hAlg = 1;
const _hKid = 4;
const _hIv = 5;

/// MOSIP Claim 169 thumb fingerprint keys: 50=right thumb, 55=left thumb.
const _fingerClaimKeys = [50, 55];

/// Face template versions.
const _faceTemplateV2Version = 0x02;
const _faceTemplateV2Len = 132;
const _faceTemplateV3Version = 0x03;
const _faceTemplateV3Len = 68;

String _kidHexFromMap(CborMap unprotected) {
  final kid = unprotected[CborSmallInt(_hKid)];
  if (kid == null) return '';
  return _asBytes(kid).map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

/// Verifies a `COSE_Sign1` array value. Returns the payload bytes.
/// `checkKid` applies to encrypted QRs only (id-free verification uses
/// the key directly, like the backend).
Future<Uint8List> _sign1Verify(
  CborValue node, {
  required bool checkKid,
  String kidHex = IssuerPin.kid,
  String? publicKeyBase64Url,
}) async {
  final arr = _asList(node);
  if (arr.length != 4 || !arr.tags.contains(_tagSign1)) {
    throw const FormatException('auth-failed');
  }
  final protectedBytes = _asBytes(arr[0]);
  final protectedMap = _asMap(_decodeCbor(protectedBytes));
  if (_optInt(protectedMap[CborSmallInt(_hAlg)]) != _algEddsa) {
    throw const FormatException('auth-failed');
  }
  if (checkKid) {
    final unprotected = arr[1] is CborMap ? arr[1] as CborMap : null;
    final gotHex = unprotected == null ? '' : _kidHexFromMap(unprotected);
    if (gotHex != kidHex) {
      throw const FormatException('unknown-key');
    }
  }
  final payload = _asBytes(arr[2]);
  final signature = _asBytes(arr[3]);
  final toVerify = Uint8List.fromList(_encodeCbor(CborList([
    CborString('Signature1'),
    CborBytes(protectedBytes),
    CborBytes(Uint8List(0)),
    CborBytes(payload),
  ])));
  final ok = await Ed25519().verify(
    toVerify,
    signature: Signature(
      signature,
      publicKey: SimplePublicKey(
        base64Url.decode(base64Url.normalize(
            publicKeyBase64Url ?? IssuerPin.publicKeyBase64Url)),
        type: KeyPairType.ed25519,
      ),
    ),
  );
  if (!ok) throw const FormatException('auth-failed');
  return payload;
}

/// Decrypts a `COSE_Encrypt0` CWT value with the CEK (`ENCRYPTION_KEY`).
Future<Uint8List> _encrypt0Decrypt(CborValue node, Uint8List cek) async {
  final arr = _asList(node);
  if (arr.length != 3 || !arr.tags.contains(_tagCwt)) {
    throw const FormatException('malformed-qr');
  }
  final protectedBytes = _asBytes(arr[0]);
  final protectedMap = _asMap(_decodeCbor(protectedBytes));
  if (_optInt(protectedMap[CborSmallInt(_hAlg)]) != _algA256gcm) {
    throw const FormatException('auth-failed');
  }
  final unprotected = arr[1] is CborMap ? arr[1] as CborMap : null;
  final iv = unprotected == null ? Uint8List(0) : _asBytes(unprotected[CborSmallInt(_hIv)]);
  if (iv.length != 12) throw const FormatException('auth-failed');
  final raw = _asBytes(arr[2]);
  if (raw.length < 17) throw const FormatException('auth-failed');
  final ct = raw.sublist(0, raw.length - 16);
  final tag = raw.sublist(raw.length - 16);
  final aad = Uint8List.fromList(_encodeCbor(CborList([
    CborString('Encrypt0'),
    CborBytes(protectedBytes),
    CborBytes(Uint8List(0)),
  ])));
  try {
    final plain = await AesGcm.with256bits().decrypt(
      SecretBox(ct, nonce: iv, mac: Mac(tag)),
      secretKey: SecretKey(cek),
      aad: aad,
    );
    return Uint8List.fromList(plain);
  } on SecretBoxAuthenticationError {
    throw const FormatException('auth-failed');
  }
}

Uint8List _inflate(Uint8List bytes) {
  try {
    return Uint8List.fromList(ZLibDecoder().decodeBytes(bytes));
  } catch (_) {
    throw const FormatException('malformed-qr');
  }
}

// ---------------------------------------------------------------- Face biometrics (key 62)

/// Parses identity key 62 as a `[Biometrics]` entry: `[{0: bstr, 1: int, 2: int}]`.
/// Returns the face template bytes. Throws on legacy formats.
Uint8List _parseFaceBiometrics(CborValue value) {
  if (value is! CborList || value.isEmpty || value[0] is! CborMap) {
    throw const FormatException('malformed-qr');
  }
  final entry = value[0] as CborMap;
  final buf = _asBytes(entry[CborSmallInt(0)]);
  if (buf.length == _faceTemplateV2Len && buf[0] == _faceTemplateV2Version) {
    return buf;
  }
  if (buf.length == _faceTemplateV3Len && buf[0] == _faceTemplateV3Version) {
    return buf;
  }
  throw const FormatException('malformed-qr');
}

// ---------------------------------------------------------------- Claim 169

MosipCredential _credentialFromClaims(CborValue claims, {required String mode}) {
  final map = _asMap(claims);
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final exp = _optInt(map[CborSmallInt(4)]);
  final nbf = _optInt(map[CborSmallInt(5)]);
  if (exp != null && now > exp) throw const FormatException('expired');
  if (nbf != null && now < nbf) throw const FormatException('not-yet-valid');
  final identity = map[CborSmallInt(169)];
  if (identity is! CborMap) throw const FormatException('malformed-qr');

  String? id;
  if (mode == 'id-free') {
    if (identity[CborSmallInt(1)] != null) {
      throw const FormatException('malformed-qr');
    }
  } else {
    final idNode = identity[CborSmallInt(1)];
    id = idNode is CborString ? idNode.toString() : null;
  }

  final faceNode = identity[CborSmallInt(62)];
  if (faceNode == null) throw const FormatException('malformed-qr');
  final faceHash = _parseFaceBiometrics(faceNode);

  // Parse thumb fingerprints (keys 50 and 55 only).
  final fingerprints = <int, Uint8List>{};
  for (final key in _fingerClaimKeys) {
    final finger = identity[CborSmallInt(key)];
    final fingerEntry = finger is CborList &&
            finger.isNotEmpty &&
            finger[0] is CborMap
        ? finger[0] as CborMap
        : null;
    if (fingerEntry != null) {
      fingerprints[key] = _asBytes(fingerEntry[CborSmallInt(0)]);
    }
  }
  if (fingerprints.isEmpty) throw const FormatException('malformed-qr');

  // Primary FMR: key 50 (right thumb), falling back to first available.
  final primaryFmr =
      fingerprints[50] ?? fingerprints[fingerprints.keys.first]!;

  final nameNode = identity[CborSmallInt(4)];
  final dobNode = identity[CborSmallInt(8)];
  final found = _findPortrait(identity);
  return MosipCredential(
    qrMode: mode,
    iss: map[CborSmallInt(1)] is CborString
        ? (map[CborSmallInt(1)] as CborString).toString()
        : IssuerPin.iss,
    exp: exp,
    nbf: nbf,
    iat: _optInt(map[CborSmallInt(6)]),
    id: id,
    name: nameNode is CborString ? nameNode.toString() : '',
    dob: dobNode is CborString ? dobNode.toString() : '',
    faceHash: faceHash,
    fmr: primaryFmr,
    fingerprints: fingerprints,
    portrait: found.bytes,
    portraitInfo: found.info,
  );
}

// ---------------------------------------------------------------- Portrait hunt (unchanged)

class _PortraitFind {
  const _PortraitFind(this.bytes, this.info);
  final Uint8List? bytes;
  final PortraitInfo? info;
}

class PortraitInfo {
  const PortraitInfo({
    required this.key,
    required this.format,
    required this.bytes,
  });
  final int key;
  final String format;
  final int bytes;
}

_PortraitFind _findPortrait(CborMap identity) {
  final keys = identity.keys.whereType<CborInt>().map((k) => k.toInt()).toList()
    ..sort();
  final ordered = [
    if (keys.contains(63)) 63,
    for (final k in keys)
      if (k != 63) k,
  ];
  _PortraitFind? infoOnly;
  for (final passRenderable in [true, false]) {
    for (final k in ordered) {
      final raw = _coerceBytes(identity[CborSmallInt(k)]);
      if (raw == null) continue;
      final kind = _classifyImage(raw);
      if (kind == null) continue;
      if (kind.renderable) {
        return _PortraitFind(
            kind.bytes,
            PortraitInfo(
                key: k, format: kind.format, bytes: raw.length));
      }
      infoOnly ??= _PortraitFind(
          null,
          PortraitInfo(
              key: k, format: kind.format, bytes: raw.length));
      if (!passRenderable) return infoOnly;
    }
  }
  return const _PortraitFind(null, null);
}

Uint8List? _coerceBytes(CborValue? node) {
  if (node is CborBytes) return Uint8List.fromList(node.bytes);
  if (node is CborString) {
    try {
      return Uint8List.fromList(
          base64.decode(base64.normalize(node.toString().trim())));
    } catch (_) {
      return null;
    }
  }
  return null;
}

class _ImageKind {
  const _ImageKind(this.format, this.bytes, this.renderable);
  final String format;
  final Uint8List bytes;
  final bool renderable;
}

_ImageKind? _classifyImage(Uint8List raw) {
  if (raw.length >= 3 && raw[0] == 0xFF && raw[1] == 0xD8) {
    return _ImageKind('jpeg', raw, true);
  }
  if (raw.length >= 8 &&
      raw[0] == 0x89 &&
      raw[1] == 0x50 &&
      raw[2] == 0x4E &&
      raw[3] == 0x47) {
    return _ImageKind('png', raw, true);
  }
  if (_isJp2(raw)) return _ImageKind('jp2', raw, false);
  if (raw.isNotEmpty && raw[0] == 0x65) {
    final jp2 = _extractJp2FromBdb(raw);
    if (jp2 != null) return _ImageKind('bdb', jp2, false);
  }
  return null;
}

bool _isJp2(Uint8List b) {
  if (b.length >= 12 &&
      b[0] == 0x00 &&
      b[1] == 0x00 &&
      b[2] == 0x00 &&
      b[3] == 0x0C &&
      b[4] == 0x6A &&
      b[5] == 0x50) {
    return true;
  }
  return b.length >= 2 && b[0] == 0xFF && b[1] == 0x4F;
}

(int tag, int hdr, Uint8List value)? _readTlv(Uint8List buf, int pos) {
  if (pos + 2 > buf.length) return null;
  final lb = buf[pos + 1];
  int hdr, len;
  if (lb < 0x80) {
    hdr = 2;
    len = lb;
  } else {
    final n = lb & 0x7f;
    if (n == 0 || n > 4 || pos + 2 + n > buf.length) return null;
    hdr = 2 + n;
    len = 0;
    for (var i = 0; i < n; i++) {
      len = (len << 8) | buf[pos + 2 + i];
    }
  }
  if (pos + hdr + len > buf.length) return null;
  return (buf[pos], hdr, buf.sublist(pos + hdr, pos + hdr + len));
}

List<(int, int, Uint8List)>? _children(Uint8List value) {
  final out = <(int, int, Uint8List)>[];
  var p = 0;
  while (p < value.length) {
    final t = _readTlv(value, p);
    if (t == null) return null;
    out.add(t);
    p += t.$2 + t.$3.length;
  }
  return out;
}

(int, int, Uint8List)? _findChild(
    List<(int, int, Uint8List)> kids, int tag) {
  for (final k in kids) {
    if (k.$1 == tag) return k;
  }
  return null;
}

Uint8List? _extractJp2FromBdb(Uint8List buf) {
  if (buf.length < 4 || buf[0] != 0x65) return null;
  var node = _readTlv(buf, 0);
  if (node == null) return null;
  var kids = _children(node.$3);
  if (kids == null) return null;
  for (final tag in [0xA1, 0x30, 0xA1, 0xA0, 0xA0]) {
    final next = _findChild(kids!, tag);
    if (next == null) return null;
    kids = _children(next.$3);
    if (kids == null) return null;
  }
  final octet = _findChild(kids!, 0x80);
  if (octet == null) return null;
  if (!_isJp2(octet.$3)) return null;
  return octet.$3;
}

// ---------------------------------------------------------------- verify

Future<MosipCredential> verifyQrTextOffline(
  String qrText, {
  Uint8List? cekOverride,
  String kidHex = IssuerPin.kid,
  String? publicKeyBase64Url,
}) async {
  final text = qrText.trim().toUpperCase();
  if (text.isEmpty) throw const FormatException('malformed-qr');
  final raw = base45Decode(text);

  CborValue? outer;
  try {
    outer = cbor.decode(raw);
  } catch (_) {
    outer = null;
  }

  if (outer is CborList && outer.tags.contains(_tagCwt)) {
    final key = cekOverride ?? eidKeyBytes();
    if (key.length != 32) throw const FormatException('auth-failed');
    final compressed = await _encrypt0Decrypt(outer, key);
    final signed = _inflate(compressed);
    final signObj = _decodeCbor(signed);
    final payload = await _sign1Verify(signObj,
        checkKid: true, kidHex: kidHex,
        publicKeyBase64Url: publicKeyBase64Url);
    return _credentialFromClaims(_decodeCbor(payload), mode: 'encrypted');
  }

  // Id-free: raw deflate of Tag(18) Sign1.
  final signed = _inflate(raw);
  final signObj = _decodeCbor(signed);
  final payload = await _sign1Verify(signObj,
      checkKid: false, kidHex: kidHex,
      publicKeyBase64Url: publicKeyBase64Url);
  return _credentialFromClaims(_decodeCbor(payload), mode: 'id-free');
}

// ------------------------------------------------------------------ inspect

class QrInspection {
  const QrInspection({
    required this.qrMode,
    required this.iss,
    required this.entries,
  });
  final String qrMode;
  final String iss;
  final List<(String, String)> entries;
}

String _headHex(List<int> bytes, [int n = 8]) => bytes
    .take(n)
    .map((e) => e.toRadixString(16).padLeft(2, '0'))
    .join(' ');

String _describeValue(CborValue? v) {
  if (v == null) return 'absent';
  if (v is CborBytes) {
    final b = v.bytes;
    final magic = _guessMagic(b);
    return 'bstr ${b.length}B head[${_headHex(b)}]${magic == null ? '' : ' ~$magic'}';
  }
  if (v is CborString) {
    final s = v.toString();
    final preview = s.length > 40 ? '${s.substring(0, 40)}…' : s;
    return 'tstr ${s.length}ch "$preview"';
  }
  if (v is CborInt) return 'int ${v.toInt()}';
  if (v is CborList) {
    if (v.isNotEmpty && v[0] is CborMap) {
      final first = v[0] as CborMap;
      final inner = first[CborSmallInt(0)];
      final size = inner is CborBytes ? '${inner.bytes.length}B' : '?';
      return 'list[${v.length}] map[0].bstr=$size head[${inner is CborBytes ? _headHex(inner.bytes) : '-'}]';
    }
    return 'list[${v.length}]';
  }
  if (v is CborMap) return 'map[${v.length} keys]';
  return v.runtimeType.toString();
}

String? _guessMagic(List<int> b) {
  if (b.length >= 2 && b[0] == 0xFF && b[1] == 0xD8) return 'JPEG?';
  if (b.length >= 12 &&
      b[4] == 0x66 &&
      b[5] == 0x74 &&
      b[6] == 0x79 &&
      b[7] == 0x70) {
    return 'ISO-BMFF/JP2?';
  }
  if (b.length >= 2 && b[0] == 0x65) return 'DER-BDB?';
  if (b.length == 132 && b[0] == 0x02) return 'face-template-v2?';
  if (b.length == 68 && b[0] == 0x03) return 'face-template-v3?';
  return null;
}

Future<QrInspection> inspectQrTextOffline(String qrText,
    {Uint8List? cekOverride}) async {
  final entries = <(String, String)>[];
  final text = qrText.trim().toUpperCase();
  if (text.isEmpty) throw const FormatException('malformed-qr');
  final raw = base45Decode(text);
  entries.add(('qrText', '${text.length} chars Base45'));
  entries.add(('rawBytes', '${raw.length}B'));

  CborValue? outer;
  try {
    outer = cbor.decode(raw);
  } catch (_) {
    outer = null;
  }
  final encrypted = outer is CborList && outer.tags.contains(_tagCwt);
  entries.add(('mode', encrypted ? 'encrypted (Tag 61)' : 'id-free (deflate)'));

  late CborValue signObj;
  if (encrypted) {
    final key = cekOverride ?? eidKeyBytes();
    if (key.length != 32) throw const FormatException('need-CEK');
    signObj = _decodeCbor(_inflate(await _encrypt0Decrypt(outer, key)));
  } else {
    signObj = _decodeCbor(_inflate(raw));
  }
  final arr = _asList(signObj);
  if (arr.length != 4) throw const FormatException('malformed-qr');
  final claims = _decodeCbor(_asBytes(arr[2]));
  final map = _asMap(claims);
  final issNode = map[CborSmallInt(1)];
  final iss = issNode is CborString ? issNode.toString() : '(?)';
  entries.add(('claim[1] iss', iss));
  for (final k in [4, 5, 6]) {
    entries.add(('claim[$k]', _describeValue(map[CborSmallInt(k)])));
  }
  final identity = map[CborSmallInt(169)];
  if (identity is! CborMap) throw const FormatException('malformed-qr');
  final keys = identity.keys
      .map((k) => k is CborInt ? k.toInt().toString() : '?')
      .toList();
  entries.add(('identity keys', keys.join(', ')));
  for (final k in identity.keys) {
    final label = k is CborInt ? 'identity[${k.toInt()}]' : 'identity[?]';
    entries.add((label, _describeValue(identity[k])));
  }
  return QrInspection(
      qrMode: encrypted ? 'encrypted' : 'id-free',
      iss: iss,
      entries: entries);
}
