import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/face_matcher.dart';
import 'package:qr_identity/services/face_model_pack.dart';
import 'package:qr_identity/services/face_projection.dart';
import 'package:qr_identity/services/mosip.dart';

Uint8List _hashOfBits(List<int> bits) {
  assert(bits.length == 512);
  final out = Uint8List(65)..[0] = 0x01;
  for (var i = 0; i < 512; i++) {
    if (bits[i] == 1) out[1 + (i ~/ 8)] |= (1 << (7 - (i % 8)));
  }
  return out;
}

/// 132B template of the normalized `vec`, backend-style (rint + int8).
Uint8List _templateOf(List<double> vec) {
  final n = sqrt(vec.fold<double>(0, (s, x) => s + x * x));
  final t = Uint8List(132)
    ..[0] = 0x02
    ..[1] = 0x01
    ..[2] = 0x80
    ..[3] = 0x7f;
  for (var i = 0; i < 128; i++) {
    final q = ((vec[i] / n).clamp(-1.0, 1.0) * 127).round();
    t[4 + i] = q < 0 ? q + 256 : q;
  }
  return t;
}

final _dummyCredential = MosipCredential(
  qrMode: 'id-free',
  iss: 'https://test.invalid',
  exp: null,
  nbf: null,
  iat: null,
  id: null,
  name: 'Test',
  dob: '20000101',
  faceHash: Uint8List(0),
  fmr: Uint8List(0),
  fingerprints: {50: Uint8List(0)},
  portrait: null,
  portraitInfo: null,
);

void main() {
  test('thresholds: hash 0.60, edge template 0.40, legacy 0.35', () {
    // Template thresholds recalibrated Sep 2026 per embedding space:
    // EdgeFace-S (genuine >= 0.73, impostors <= 0.13), w600k_mbf legacy
    // (genuine >= 0.61, impostors <= 0.16).
    expect(FaceMatcher.hashThreshold, 0.60);
    expect(FaceMatcher.templateThreshold, 0.40);
    expect(FaceMatcher.legacyTemplateThreshold, 0.35);
    expect(FaceMatcher.backend, contains('edgeface-s'));
    expect(FaceMatcher.legacyBackend, contains('buffalo-mbf'));
  });

  test('pickMatch: current QR wins on edge margin', () {
    final v = FaceMatcher.pickMatch(
        edgeScore: 0.74, legacyScore: 0.08, isTemplate: true);
    expect(v.match, isTrue);
    expect(v.backend, FaceMatcher.backend);
    expect(v.score, 0.74);
    expect(v.threshold, 0.40);
  });

  test('pickMatch: legacy buffalo QR wins on legacy margin', () {
    // Real field case: buffalo-issued 68B template scores garbage in
    // EdgeFace space (-0.204) but matches in mbf space.
    final v = FaceMatcher.pickMatch(
        edgeScore: -0.204, legacyScore: 0.61, isTemplate: true);
    expect(v.match, isTrue);
    expect(v.backend, FaceMatcher.legacyBackend);
    expect(v.score, 0.61);
    expect(v.threshold, 0.35);
  });

  test('pickMatch: mismatch reports max-margin space', () {
    final v = FaceMatcher.pickMatch(
        edgeScore: 0.39, legacyScore: 0.20, isTemplate: true);
    expect(v.match, isFalse);
    expect(v.backend, FaceMatcher.backend);
    expect(v.score, 0.39);
  });

  test('pickMatch: hash path uses 0.60 in both spaces', () {
    final v = FaceMatcher.pickMatch(
        edgeScore: 0.50, legacyScore: 0.65, isTemplate: false);
    expect(v.match, isTrue);
    expect(v.backend, FaceMatcher.legacyBackend);
    expect(v.threshold, 0.60);
  });

  test('scoreHash: identical embedding scores 1.0', () {
    final bits = List.generate(512, (i) => i % 3 == 0 ? 1 : 0);
    final emb =
        List<double>.generate(512, (i) => bits[i] == 1 ? 0.5 : -0.5);
    expect(FaceMatcher.scoreHash(_hashOfBits(bits), emb),
        closeTo(1.0, 1e-9));
  });

  test('scoreHash: opposite embedding scores 0.0', () {
    final bits = List.generate(512, (i) => i % 2);
    final emb =
        List<double>.generate(512, (i) => bits[i] == 1 ? -0.5 : 0.5);
    expect(FaceMatcher.scoreHash(_hashOfBits(bits), emb),
        closeTo(0.0, 1e-9));
  });

  test('scoreHash: half bits differ scores 0.5', () {
    final emb =
        List<double>.generate(512, (i) => i < 256 ? 0.5 : -0.5);
    expect(FaceMatcher.scoreHash(_hashOfBits(List.filled(512, 1)), emb),
        closeTo(0.5, 1e-9));
  });

  test('scoreHash rejects bad versions/dims', () {
    expect(() => FaceMatcher.scoreHash(Uint8List(65), List.filled(512, 0.1)),
        throwsFormatException);
    expect(
        () => FaceMatcher.scoreHash(
            _hashOfBits(List.filled(512, 1)), List.filled(100, 0.1)),
        throwsFormatException);
  });

  test('scoreTemplate: identical vector scores ~1.0', () {
    final live = List<double>.generate(128, (i) => (i % 7) - 3.0);
    expect(FaceMatcher.scoreTemplate(_templateOf(live), live),
        closeTo(1.0, 0.02));
  });

  test('scoreTemplate: dissimilar vectors score low', () {
    final a = List<double>.generate(128, (i) => i < 64 ? 1.0 : -1.0);
    final b = List<double>.generate(128, (i) => (i % 2 == 0) ? 1.0 : -1.0);
    expect(FaceMatcher.scoreTemplate(_templateOf(a), b).abs(),
        lessThan(0.3));
  });

  test('scoreTemplate rejects bad headers/dims', () {
    expect(
        () => FaceMatcher.scoreTemplate(
            Uint8List(132), List.filled(128, 0.1)),
        throwsFormatException);
    expect(
        () => FaceMatcher.scoreTemplate(
            _templateOf(List.filled(128, 0.1)), List.filled(64, 0.1)),
        throwsFormatException);
  });

  test('scoreTemplateV3: identical vector scores ~1.0', () {
    final live = List<double>.generate(64, (i) => (i % 5) - 2.0);
    final n = sqrt(live.fold<double>(0, (s, x) => s + x * x));
    final t = Uint8List(68)
      ..[0] = 0x03
      ..[1] = 0x02
      ..[2] = 0x40
      ..[3] = 0x7f;
    for (var i = 0; i < 64; i++) {
      final q = ((live[i] / n).clamp(-1.0, 1.0) * 127).round();
      t[4 + i] = q < 0 ? q + 256 : q;
    }
    expect(FaceMatcher.scoreTemplateV3(t, live), closeTo(1.0, 0.02));
  });

  test('scoreTemplateV3 rejects bad headers/dims', () {
    expect(
        () => FaceMatcher.scoreTemplateV3(
            Uint8List(68), List.filled(64, 0.1)),
        throwsFormatException);
    expect(
        () => FaceMatcher.scoreTemplateV3(
            Uint8List.fromList(
                [0x03, 0x02, 0x40, 0x7f, ...List.filled(64, 10)]),
            List.filled(128, 0.1)),
        throwsFormatException);
  });

  test('projection64 matches numpy reference (seed 6403)', () {
    final emb = List<double>.generate(512, (i) => sin(i * 0.7));
    final proj = FaceProjection.project64(emb);
    expect(proj.length, 64);
    const expected = [
      0.015075339,
      -0.141978875,
      -0.068951681,
      0.317392796,
      0.006732265,
      0.084280603,
      0.025465693,
      0.101304524,
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(proj[i], closeTo(expected[i], 1e-6));
    }
    var norm = 0.0;
    for (final v in proj) {
      norm += v * v;
    }
    expect(sqrt(norm), closeTo(1.0, 1e-9));
  });

  test('projection matches numpy reference (seed 39794)', () {
    final emb = List<double>.generate(512, (i) => sin(i * 0.7));
    final proj = FaceProjection.project(emb);
    expect(proj.length, 128);
    const expected = [
      -0.166284976,
      0.055742592,
      0.006214556,
      -0.155890499,
      -0.017044431,
      0.074904332,
      0.194458639,
      -0.076303522,
    ];
    for (var i = 0; i < expected.length; i++) {
      expect(proj[i], closeTo(expected[i], 1e-6));
    }
    var norm = 0.0;
    for (final v in proj) {
      norm += v * v;
    }
    expect(sqrt(norm), closeTo(1.0, 1e-9));
  });

  test('matcher without model pack throws ModelPackMissing', () async {
    FaceMatcher.resetEngineForTest();
    try {
      await FaceMatcher().matchSelfieVsQr(
        selfieBytes: Uint8List.fromList([1, 2, 3]),
        credential: _dummyCredential,
        pack: FaceModelPack(Directory('/nonexistent-dir-xyz')),
      );
      fail('must throw ModelPackMissing');
    } on ModelPackMissing catch (e) {
      expect(e.missingBytes, greaterThan(0));
    }
  });
}
