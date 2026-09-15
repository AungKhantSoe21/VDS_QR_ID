import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/face_embedder.dart';

RgbImage _gradient8() {
  final bytes = Uint8List(8 * 8 * 3);
  var o = 0;
  for (var y = 0; y < 8; y++) {
    for (var x = 0; x < 8; x++) {
      bytes[o++] = x * 32;
      bytes[o++] = y * 32;
      bytes[o++] = (x + y) * 16;
    }
  }
  return RgbImage(8, 8, bytes);
}

void main() {
  test('estimateNorm matches numpy lstsq reference', () {
    // Landmarks + M from the Python reference (ref.py + numpy lstsq).
    final kps = [
      [67.87052917480469, 109.76482391357422],
      [105.672607421875, 113.88349914550781],
      [75.12210845947266, 141.8516387939453],
      [71.12077331542969, 150.34825134277344],
      [107.89737701416016, 154.1920928955078],
    ];
    const expected = [
      0.872494190,
      -0.009481092,
      -19.874638652,
      -44.209492381,
    ];
    final abtt = FaceAlign.estimateNorm(kps);
    for (var i = 0; i < 4; i++) {
      // Normal-equations solver vs numpy SVD lstsq: tiny conditioning
      // noise (relative ~1e-7), far below pixel significance.
      expect(abtt[i], closeTo(expected[i], 2e-5));
    }
  });

  test('warp identity reproduces input exactly', () {
    final out = FaceAlign.warp(_gradient8(), [1.0, 0.0, 0.0, 0.0], 8);
    expect(out.bytes, _gradient8().bytes);
  });

  test('warp shift matches cv2.warpAffine reference', () {
    // cv2.warpAffine(grad, [[0.5,0,1],[0,0.5,2]], (8,8), border 0).
    final out = FaceAlign.warp(_gradient8(), [0.5, 0.0, 1.0, 2.0], 8);
    const expectedRow3 = [
      0, 0, 0, //
      0, 64, 32, //
      64, 64, 64, //
      128, 64, 96, //
      192, 64, 128,
    ];
    final row = out.bytes.sublist(3 * 8 * 3, 3 * 8 * 3 + 15);
    expect(row, expectedRow3);
    // Row 0 maps fully out of bounds -> zeros.
    expect(out.bytes.sublist(0, 24), List.filled(24, 0));
  });

  test('scrfd decode finds candidate and NMS suppresses overlap', () {
    List<List<double>> zeros(int n, int cols) =>
        List.generate(n, (_) => List.filled(cols, 0.0));
    final scores = [zeros(12800, 1), zeros(3200, 1), zeros(800, 1)];
    final boxes = [zeros(12800, 4), zeros(3200, 4), zeros(800, 4)];
    final kpss = [zeros(12800, 10), zeros(3200, 10), zeros(800, 10)];
    // Anchor (0,0) stride 8, two overlapping boxes.
    scores[0][0][0] = 0.9;
    boxes[0][0] = [0.0, 0.0, 1.25, 1.25]; // -> [0,0,10,10]
    scores[0][1][0] = 0.8;
    boxes[0][1] = [-0.125, -0.125, 1.125, 1.125]; // -> [-1,-1,9,9]
    final dets = ScrfdDecoder.decode(
        scores: scores, bboxes: boxes, kpss: kpss, scale: 1.0);
    expect(dets.length, 1);
    expect(dets.first.score, closeTo(0.9, 1e-9));
    expect(dets.first.bbox[2], closeTo(10.0, 1e-9));
  });

  test('scrfd decode is empty below threshold', () {
    List<List<double>> zeros(int n, int cols) =>
        List.generate(n, (_) => List.filled(cols, 0.0));
    final dets = ScrfdDecoder.decode(
      scores: [zeros(12800, 1), zeros(3200, 1), zeros(800, 1)],
      bboxes: [zeros(12800, 4), zeros(3200, 4), zeros(800, 4)],
      kpss: [zeros(12800, 10), zeros(3200, 10), zeros(800, 10)],
      scale: 2.0,
    );
    expect(dets, isEmpty);
    expect(ScrfdDecoder.largest(dets), isNull);
  });

  test('recBlob normalizes solid color exactly', () {
    final solid = RgbImage(112, 112, Uint8List(112 * 112 * 3)..fillRange(0, 112 * 112 * 3, 200));
    final blob = BlobPrep.recBlob(solid);
    expect(blob.length, 3 * 112 * 112);
    expect(blob[0], closeTo((200 - 127.5) / 127.5, 1e-6));
    expect(blob[112 * 112], closeTo((200 - 127.5) / 127.5, 1e-6));
  });

  test('detBlob has NCHW shape and letterbox scale', () {
    final tiny = RgbImage(2, 1, Uint8List.fromList([10, 20, 30, 40, 50, 60]));
    final input = BlobPrep.detBlob(tiny);
    expect(input.blob.length, 3 * 640 * 640);
    expect(input.scale, closeTo(640 / 2, 1e-9));
  });
}
