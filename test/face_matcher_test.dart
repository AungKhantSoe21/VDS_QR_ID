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
  test('hash threshold defaults to field-calibrated 0.60', () {
    // Backend lab default was 0.55; field data (genuine ~0.79, stranger
    // >0.55) moved the shipped default up. Template scale is separate.
    expect(FaceMatcher.hashThreshold, 0.60);
    expect(FaceMatcher.templateThreshold, 0.30);
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
