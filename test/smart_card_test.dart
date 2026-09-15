import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:qr_identity/models/card_data.dart';
import 'package:qr_identity/services/eid_codec.dart';
import 'package:qr_identity/services/eid_crypto.dart';
import 'package:qr_identity/services/eid_parser.dart';
import 'package:qr_identity/config/eid_key.dart';
import 'package:qr_identity/services/face_matcher.dart';
import 'package:qr_identity/services/mosip.dart';
import 'package:qr_identity/widgets/smart_card.dart';

// Same real backend-signed id-free vector as mosip_test.dart.
const _backendQrText =
    'NCFOXNESSMTI4EFQSK-AH2OUUS246CTUKR964NIBNVF/8NX88JA+BB3PQ4M5PF6O:5\$NP41AEYP9\$PXXADB9V-5%DP0%M+Q6A46G66SDM:%N/GPKAJPOKEIH0IKL-BLCRTTR%K6GR7AZ6\$EN HI62CZ+AEZR/SQD/RUQ63D7%EM:1KK1BSIBSYQ6-RR.QN47O96IAOD1JDOB.HAU%BK+QKKR\$36W%7W9N6OJRNA5UB:\$ADIRENQH:71%6PWNKNI-*JJTA\$FBRHQM7SV/6*F7*VMU\$NA*IC7BDCA7DS 6ROL78F6-Z7: M3HJ08A5II2B9% 8W51WZK3/9:D3PF6EA6\$87MZANX6+/EFMN JQ:9TI*O:-RUM9DGDKD2 UJZ/P4NQ/+0ENRYREUODU6JLDH7LPI-VE7OT0PM7UN5KS5IJV8W2S0252JBI5C:CAV50SGC:-I';

// Dedicated test key (never the server key): 32 bytes of 0x0b.
const _testKeyHex =
    '0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b0b';

// 1x1 PNG bytes reused as fake legacy thumbs.
const _tinyPngB64 =
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==';

Future<CardData> _legacyCard() async {
  final crypto = EidCrypto(keyBytes: hexDecode(_testKeyHex));
  final bytes = base64.decode(_tinyPngB64);
  final payload = EidCodec.encodePayloadV3(
    id: 'uuid-test-1',
    ts: '2026-09-09T00:00:00Z',
    name: 'Legacy User',
    idNumber: 'L-009',
    fmt: 'jpeg',
    passport: Uint8List.fromList(bytes),
    fingerprint: Uint8List.fromList(bytes),
  );
  final enc = await crypto.encrypt(payload);
  final envelope = EidCodec.encodeEnvelope(
    version: 3,
    iv: enc.iv,
    tag: enc.tag,
    ct: enc.ct,
  );
  final rec = await EidParser(
    crypto: EidCrypto(keyBytes: hexDecode(_testKeyHex)),
  ).parseEnvelopeBytes(envelope);
  return CardData.fromLegacy(rec, EidParser.envelopeToQrText(envelope));
}

Future<void> _pumpCard(WidgetTester tester, SmartCardFlip card) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: Center(child: SizedBox(width: 360, child: card)),
      ),
    ),
  );
  await tester.pump();
}

const _match = FaceMatchResult(
  FaceMatchStatus.match,
  score: 0.79,
  threshold: 0.60,
);

void main() {
  testWidgets('VDS front: header, QR, dates footer, no portrait', (
    WidgetTester tester,
  ) async {
    final credential = await verifyQrTextOffline(_backendQrText);
    await _pumpCard(
      tester,
      SmartCardFlip(
        card: CardData.fromMosip(credential, _backendQrText),
        faceMatch: _match,
        externalFinger: null,
      ),
    );
    // Header per id_layout_card.md (real asset with painted fallback).
    expect(find.byKey(const Key('emblem')), findsOneWidget);
    expect(find.byKey(const Key('flag')), findsOneWidget);
    expect(find.text('THE REPUBLIC OF THE UNION OF MYANMAR'), findsWidgets);
    // Info only: no portrait box, no placeholder.
    expect(find.byKey(const Key('portrait')), findsNothing);
    expect(find.byKey(const Key('portrait-placeholder')), findsNothing);
    // QR lives on the front, filling its column.
    final qr = tester.widget<QrImageView>(find.byType(QrImageView));
    expect(qr.size, 96);
    // Fields.
    expect(find.text('အမည် / Name'), findsOneWidget);
    expect(find.text('Offline Test'), findsOneWidget);
    expect(find.text('UID No.'), findsOneWidget);
    expect(find.text('နိုင်ငံသားစိစစ်ရေးကတ်ပြားအမှတ်'), findsOneWidget);
    expect(find.text('Date Of Birth'), findsOneWidget);
    expect(find.text('Gender'), findsOneWidget);
    expect(find.text('Date Of Expiry'), findsOneWidget);
    expect(find.byKey(const Key('border-strip')), findsOneWidget);
    // Flip to the back: VDS back mock layout — full header, trail left,
    // UID reference right. Info only: no QR, no portrait, no MRZ.
    await tester.tap(find.byType(SmartCardFlip));
    await tester.pumpAndSettle();
    expect(find.byType(QrImageView), findsNothing);
    expect(find.byKey(const Key('portrait')), findsNothing);
    expect(find.byKey(const Key('portrait-placeholder')), findsNothing);
    expect(find.text('THE REPUBLIC OF THE UNION OF MYANMAR'), findsOneWidget);
    expect(find.text('QR authentic (offline)'), findsOneWidget);
    expect(find.text('Verified fully offline'), findsOneWidget);
    expect(find.textContaining('Fingerprint: skipped'), findsOneWidget);
  });

  testWidgets('legacy card shows record fields + visual trail', (
    WidgetTester tester,
  ) async {
    final card = await _legacyCard();
    expect(card.qrMode, 'legacy-v3');
    expect(card.nationalReg, 'L-009');
    expect(card.faceHash, isNull);
    await _pumpCard(
      tester,
      SmartCardFlip(
        card: card,
        faceMatch: null,
        visualCheck: true,
        externalFinger: null,
      ),
    );
    expect(find.text('Legacy User'), findsOneWidget);
    expect(find.text('L-009'), findsOneWidget);
    expect(find.text('FACE: VISUAL CHECK'), findsNothing); // front first
    await tester.tap(find.byType(SmartCardFlip));
    await tester.pumpAndSettle();
    expect(find.textContaining('VISUAL CHECK'), findsOneWidget);
  });

  test('card data mapping covers both QR formats', () async {
    final mosip = CardData.fromMosip(
      await verifyQrTextOffline(_backendQrText),
      'T',
    );
    expect(mosip.name, 'Offline Test');
    expect(mosip.dob, '19900101');
    expect(mosip.qrMode, 'mosip-id-free');
    expect(mosip.faceHash?.length, 132);
    expect(mosip.portrait, isNull);

    final legacy = await _legacyCard();
    expect(legacy.uid, 'uuid-test-1');
    expect(legacy.nationalReg, 'L-009');
    expect(legacy.dob, '');
    expect(legacy.credential, isNull);
    expect(legacy.portrait, isNotNull);
    expect(fmtDateLong(legacy.dob), '—');
  });

  test('date helpers format like the layout spec', () {
    expect(fmtDateLong('19951111'), '11 Nov 1995');
    expect(fmtDateLong(''), '—');
    expect(fmtDateLong('nope'), 'nope');
  });
}
