import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:cbor/cbor.dart';
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/mosip.dart';

// Real vector signed by the dev backend (`node -e issueIdFreeQr`, agent.md
// §4): id-free QR for name 'Offline Test', dob '19900101'. Public
// credential — no secrets. Pinned dev issuer key verifies it. If the
// backend keys rotate, this test fails to signal re-pinning.
const _backendQrText =
    'NCFOXNESSMTI4EFQSK-AH2OUUS246CTUKR964NIBNVF/8NX88JA+BB3PQ4M5PF6O:5\$NP41AEYP9\$PXXADB9V-5%DP0%M+Q6A46G66SDM:%N/GPKAJPOKEIH0IKL-BLCRTTR%K6GR7AZ6\$EN HI62CZ+AEZR/SQD/RUQ63D7%EM:1KK1BSIBSYQ6-RR.QN47O96IAOD1JDOB.HAU%BK+QKKR\$36W%7W9N6OJRNA5UB:\$ADIRENQH:71%6PWNKNI-*JJTA\$FBRHQM7SV/6*F7*VMU\$NA*IC7BDCA7DS 6ROL78F6-Z7: M3HJ08A5II2B9% 8W51WZK3/9:D3PF6EA6\$87MZANX6+/EFMN JQ:9TI*O:-RUM9DGDKD2 UJZ/P4NQ/+0ENRYREUODU6JLDH7LPI-VE7OT0PM7UN5KS5IJV8W2S0252JBI5C:CAV50SGC:-I';
const _backendFaceHashPrefix = '0201807f1f262d343b424950575e656c';

Uint8List _hex(String s) => Uint8List.fromList([
      for (var i = 0; i < s.length; i += 2)
        int.parse(s.substring(i, i + 2), radix: 16)
    ]);

/// Build a 132-byte face template v2 (0x02 header).
Uint8List _v2FaceHash([List<int>? seed]) {
  final buf = Uint8List(132);
  buf[0] = 0x02;
  for (var i = 1; i < 132; i++) {
    buf[i] = seed != null ? seed[i % seed.length] : (i * 7 + 3) % 128;
  }
  return buf;
}

void main() {
  test('base45 round-trips binary data', () {
    final data = Uint8List.fromList(List.generate(300, (i) => i % 256));
    expect(base45Decode(base45Encode(data)), data);
    expect(base45Decode(base45Encode(Uint8List.fromList([7]))),
        Uint8List.fromList([7]));
  });

  test('real backend id-free QR verifies fully offline', () async {
    final c = await verifyQrTextOffline(_backendQrText);
    expect(c.qrMode, 'id-free');
    expect(c.id, isNull);
    expect(c.name, 'Offline Test');
    expect(c.dob, '19900101');
    expect(c.iss, 'https://eid.example.org');
    expect(c.faceHash.length, 132);
    expect(c.faceHash[0], 0x02);
  });

  test('real backend id-free QR face hash matches enrolled bytes', () async {
    final c = await verifyQrTextOffline(_backendQrText);
    expect(
        c.faceHash
            .sublist(0, 16)
            .map((e) => e.toRadixString(16).padLeft(2, '0'))
            .join(),
        _backendFaceHashPrefix);
    expect(c.fmr.length, 222);
  });

  test('tampered QR text fails closed', () async {
    final last = _backendQrText[_backendQrText.length - 1];
    final flip = last == 'A' ? 'B' : 'A';
    final tampered =
        _backendQrText.substring(0, _backendQrText.length - 1) + flip;
    try {
      await verifyQrTextOffline(tampered);
      fail('tampered QR must not verify');
    } on FormatException catch (e) {
      expect(
          ['auth-failed', 'malformed-qr'].contains(e.message), isTrue,
          reason: 'got ${e.message}');
    }
  });

  test('inspector dumps identity keys without verifying', () async {
    final r = await inspectQrTextOffline(_backendQrText);
    expect(r.qrMode, 'id-free');
    final keys = r.entries
        .firstWhere((e) => e.$1 == 'identity keys')
        .$2;
    expect(keys, contains('62'));
    expect(keys, contains('50'));
    expect(keys.contains('63'), isFalse);
    final face = r.entries.firstWhere((e) => e.$1 == 'identity[62]').$2;
    expect(face, contains('map[0].bstr=132B'));
  });

  test('garbage text is malformed-qr', () async {
    try {
      await verifyQrTextOffline('HELLO WORLD');
      fail('must throw');
    } on FormatException catch (e) {
      expect(e.message, 'malformed-qr');
    }
  });

  group('encrypted round-trip (Dart issue -> Dart verify)', () {
    Future<({String qrText, Uint8List cek, String kid, String pubKeyBase64Url})>
        issueEncrypted({
      required Map<String, dynamic> demo,
      required Uint8List faceHash,
      required Uint8List fmr,
      CborValue? portrait,
      Map<int, CborValue> extraFields = const {},
    }) async {
      final algorithm = Ed25519();
      final kp = await algorithm.newKeyPair();

      // kid: sha256(publicKeyBytes)[0:16] — test-only derivation.
      final pubBytes = (await kp.extractPublicKey()).bytes;
      final kidHash = await Sha256().hash(pubBytes);
      final kid = kidHash.bytes
          .take(8)
          .map((b) => b.toRadixString(16).padLeft(2, '0'))
          .join();
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      // Wrap fingerprint in biometrics entry [{0: data, 1: 1, 2: 1}]
      final fingerEntry = CborList([
        CborMap({
          CborSmallInt(0): CborBytes(fmr),
          CborSmallInt(1): CborSmallInt(1),
          CborSmallInt(2): CborSmallInt(1),
        })
      ]);

      final identity = CborMap({
        CborSmallInt(1): CborString('test-id'),
        CborSmallInt(4): CborString(demo['name'] as String),
        CborSmallInt(8): CborString(demo['dob'] as String),
        CborSmallInt(62): CborList([
          CborMap({
            CborSmallInt(0): CborBytes(faceHash),
            CborSmallInt(1): CborSmallInt(1),
            CborSmallInt(2): CborSmallInt(100),
          })
        ]),
        CborSmallInt(50): fingerEntry,
      });
      if (portrait != null) {
        identity[CborSmallInt(63)] = portrait;
      }
      for (final e in extraFields.entries) {
        identity[CborSmallInt(e.key)] = e.value;
      }
      final claims = CborMap({
        CborSmallInt(1): CborString('https://test.invalid'),
        CborSmallInt(4): CborSmallInt(now + 86400),
        CborSmallInt(5): CborSmallInt(now - 10),
        CborSmallInt(6): CborSmallInt(now),
        CborSmallInt(169): identity,
      });
      final payload = Uint8List.fromList(cbor.encode(claims));
      final protected = Uint8List.fromList(
          cbor.encode(CborMap({CborSmallInt(1): CborSmallInt(-8)})));
      final toSign = Uint8List.fromList(cbor.encode(CborList([
        CborString('Signature1'),
        CborBytes(protected),
        CborBytes(Uint8List(0)),
        CborBytes(payload),
      ])));
      final sig = await algorithm.sign(toSign, keyPair: kp);
      final signObj = CborList([
        CborBytes(protected),
        CborMap({CborSmallInt(4): CborBytes(_hex(kid))}),
        CborBytes(payload),
        CborBytes(sig.bytes),
      ], tags: const [18]);
      final compressed =
          Uint8List.fromList(ZLibEncoder().encodeBytes(cbor.encode(signObj)));
      final cek =
          Uint8List.fromList(List.generate(32, (i) => (i * 7 + 3) % 256));
      final encProtected =
          Uint8List.fromList(cbor.encode(CborMap({CborSmallInt(1): CborSmallInt(3)})));
      final iv = Uint8List.fromList(List.generate(12, (i) => i + 1));
      final aad = Uint8List.fromList(cbor.encode(CborList([
        CborString('Encrypt0'),
        CborBytes(encProtected),
        CborBytes(Uint8List(0)),
      ])));
      final box = await AesGcm.with256bits().encrypt(
        compressed,
        secretKey: SecretKey(cek),
        nonce: iv,
        aad: aad,
      );
      final ctAndTag =
          Uint8List.fromList([...box.cipherText, ...box.mac.bytes]);
      final cwt = Uint8List.fromList(
          cbor.encode(CborList([
        CborBytes(encProtected),
        CborMap({CborSmallInt(5): CborBytes(iv)}),
        CborBytes(ctAndTag),
      ], tags: const [61])));
      return (
        qrText: base45Encode(cwt),
        cek: cek,
        kid: kid,
        pubKeyBase64Url: base64Url.encode(pubBytes),
      );
    }

    test('valid encrypted QR verifies offline', () async {
      final faceHash = _v2FaceHash();
      final v = await issueEncrypted(
        demo: {'name': 'Round Trip', 'dob': '20000102'},
        faceHash: faceHash,
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.qrMode, 'encrypted');
      expect(c.id, 'test-id');
      expect(c.name, 'Round Trip');
      expect(c.dob, '20000102');
      expect(c.faceHash, faceHash);
      expect(c.fmr.length, 222);
    });

    test('embedded portrait bstr round-trips (key 63)', () async {
      final jpeg = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, 0xE0, ...List.generate(64, (i) => i % 256)]);
      final v = await issueEncrypted(
        demo: {'name': 'Portrait', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
        portrait: CborBytes(jpeg),
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, jpeg);
    });

    test('embedded portrait base64 tstr decodes (key 63)', () async {
      final jpeg = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, ...List.generate(32, (i) => (i * 3) % 256)]);
      final v = await issueEncrypted(
        demo: {'name': 'Portrait64', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
        portrait: CborString(base64.encode(jpeg)),
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, jpeg);
    });

    test('no portrait and non-JPEG portrait yield null, still valid',
        () async {
      final v = await issueEncrypted(
        demo: {'name': 'NoPhoto', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, isNull);

      final v2 = await issueEncrypted(
        demo: {'name': 'BadPhoto', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
        portrait: CborBytes(Uint8List.fromList([1, 2, 3, 4])),
      );
      final c2 = await verifyQrTextOffline(v2.qrText,
          cekOverride: v2.cek, kidHex: v2.kid,
          publicKeyBase64Url: v2.pubKeyBase64Url);
      expect(c2.portrait, isNull);
      expect(c2.name, 'BadPhoto');
    });

    Uint8List bdbWrap(Uint8List jp2) {
      List<int> tlv(int tag, List<int> v) => [tag, v.length, ...v];
      final o80 = tlv(0x80, jp2);
      final a0b = tlv(0xA0, o80);
      final a0a = tlv(0xA0, a0b);
      final a1i = tlv(0xA1, a0a);
      final r30 = tlv(0x30, a1i);
      final a1r = tlv(0xA1, r30);
      return Uint8List.fromList(tlv(0x65, a1r));
    }

    final demoHash = _v2FaceHash();
    final demoFmr =
        Uint8List.fromList(List.generate(222, (i) => i % 256));

    test('JPEG under a non-63 key is found anywhere', () async {
      final jpeg = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, 0xE0, ...List.generate(32, (i) => i % 256)]);
      final v = await issueEncrypted(
        demo: {'name': 'AnyKey', 'dob': '20000102'},
        faceHash: demoHash,
        fmr: demoFmr,
        extraFields: {70: CborBytes(jpeg)},
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, jpeg);
      expect(c.portraitInfo?.key, 70);
      expect(c.portraitInfo?.format, 'jpeg');
    });

    test('base64 tstr portrait under another key is found', () async {
      final jpeg = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, ...List.generate(32, (i) => (i * 3) % 256)]);
      final v = await issueEncrypted(
        demo: {'name': 'AnyKey64', 'dob': '20000102'},
        faceHash: demoHash,
        fmr: demoFmr,
        extraFields: {64: CborString(base64.encode(jpeg))},
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, jpeg);
    });

    test('BDB-wrapped JP2 is detected but not rendered', () async {
      final jp2 = Uint8List.fromList([
        0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, //
        0x0D, 0x0A, 0x87, 0x0A, 0x01, 0x02, 0x03, 0x04,
      ]);
      final v = await issueEncrypted(
        demo: {'name': 'BdbPhoto', 'dob': '20000102'},
        faceHash: demoHash,
        fmr: demoFmr,
        extraFields: {63: CborBytes(bdbWrap(jp2))},
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, isNull);
      expect(c.portraitInfo?.format, 'bdb');
      expect(c.portraitInfo?.key, 63);
      expect(c.name, 'BdbPhoto');
    });

    test('renderable JPEG wins over BDB at key 63', () async {
      final jpeg = Uint8List.fromList(
          [0xFF, 0xD8, 0xFF, ...List.generate(16, (i) => i % 256)]);
      final jp2 = Uint8List.fromList(
          [0x00, 0x00, 0x00, 0x0C, 0x6A, 0x50, 0x20, 0x20, 0x0D, 0x0A]);
      final v = await issueEncrypted(
        demo: {'name': 'PreferJpeg', 'dob': '20000102'},
        faceHash: demoHash,
        fmr: demoFmr,
        portrait: CborBytes(bdbWrap(jp2)),
        extraFields: {70: CborBytes(jpeg)},
      );
      final c = await verifyQrTextOffline(v.qrText,
          cekOverride: v.cek, kidHex: v.kid,
          publicKeyBase64Url: v.pubKeyBase64Url);
      expect(c.portrait, jpeg);
      expect(c.portraitInfo?.key, 70);
    });

    test('wrong CEK fails closed with auth-failed', () async {
      final v = await issueEncrypted(
        demo: {'name': 'Round Trip', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
      );
      final wrongCek = Uint8List.fromList(
          List.generate(32, (i) => (i * 7 + 4) % 256));
      try {
        await verifyQrTextOffline(v.qrText,
            cekOverride: wrongCek, kidHex: v.kid,
            publicKeyBase64Url: v.pubKeyBase64Url);
        fail('must throw');
      } on FormatException catch (e) {
        expect(e.message, 'auth-failed');
      }
    });

    test('unknown kid surfaces unknown-key', () async {
      final v = await issueEncrypted(
        demo: {'name': 'Round Trip', 'dob': '20000102'},
        faceHash: _v2FaceHash(),
        fmr: Uint8List.fromList(List.generate(222, (i) => i % 256)),
      );
      try {
        await verifyQrTextOffline(v.qrText,
            cekOverride: v.cek,
            kidHex: 'ffffffffffffffff',
            publicKeyBase64Url: v.pubKeyBase64Url);
        fail('must throw');
      } on FormatException catch (e) {
        expect(e.message, 'unknown-key');
      }
    });
  });
}
