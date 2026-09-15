import 'dart:math';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:onnxruntime/onnxruntime.dart';

import 'face_model_pack.dart';

/// On-device face embedding — Dart port of the backend pipeline
/// (`scripts/facematch.py` → InsightFace buffalo_l):
///
/// SCRFD det_10g (640 letterbox, thresh 0.5, NMS 0.4, largest face) →
/// similarity-align to 112×112 (arcface template) → w600k_r50 →
/// L2-normalized 512-d embedding.
///
/// Pure math ([ScrfdDecoder], [FaceAlign], [BlobPrep]) is dependency-free
/// and unit-tested; [OrtFaceEngine] is the thin onnxruntime glue.
class FaceDetection {
  const FaceDetection({
    required this.score,
    required this.bbox,
    required this.kps,
  });

  final double score;

  /// [x1, y1, x2, y2] in original-image pixels.
  final List<double> bbox;

  /// 5 landmarks in original-image pixels.
  final List<List<double>> kps;
}

/// Row-major RGB image.
class RgbImage {
  const RgbImage(this.width, this.height, this.bytes);

  final int width;
  final int height;

  /// Length `width*height*3`, R,G,B bytes.
  final Uint8List bytes;

  static RgbImage decode(Uint8List jpeg) {
    final decoded = img.decodeImage(jpeg);
    if (decoded == null) throw const FormatException('cannot decode image');
    final oriented = img.bakeOrientation(decoded);
    final out = Uint8List(oriented.width * oriented.height * 3);
    var o = 0;
    for (var y = 0; y < oriented.height; y++) {
      for (var x = 0; x < oriented.width; x++) {
        final p = oriented.getPixel(x, y);
        out[o++] = p.r.toInt();
        out[o++] = p.g.toInt();
        out[o++] = p.b.toInt();
      }
    }
    return RgbImage(oriented.width, oriented.height, out);
  }

  double at(int x, int y, int c) =>
      bytes[(y * width + x) * 3 + c].toDouble();
}

// ------------------------------------------------------------------ SCRFD

/// Exact port of `SCRFD.forward/detect/nms` (single 640×640 input,
/// `det_thresh=0.5`, `nms_thresh=0.4`).
class ScrfdDecoder {
  static const detSize = 640;
  static const detThresh = 0.5;
  static const nmsThresh = 0.4;
  static const strides = [8, 16, 32];

  /// `scores/bboxes/kpss`: 3 feature levels each (rows of length 1/4/10),
  /// row-major outputs for a 640×640 input (counts 12800/3200/800).
  /// `scale` = letterboxed height / original height.
  /// Returns kept detections (pre max-selection).
  static List<FaceDetection> decode({
    required List<List<List<double>>> scores,
    required List<List<List<double>>> bboxes,
    required List<List<List<double>>> kpss,
    required double scale,
  }) {
    final detScores = <double>[];
    final detBoxes = <List<double>>[];
    final detKps = <List<List<double>>>[];
    for (var level = 0; level < 3; level++) {
      final stride = strides[level];
      final hw = detSize ~/ stride;
      final s = scores[level];
      final b = bboxes[level];
      final k = kpss[level];
      var n = 0;
      for (var y = 0; y < hw; y++) {
        for (var x = 0; x < hw; x++) {
          for (var a = 0; a < 2; a++) {
            final score = s[n][0];
            if (score >= detThresh) {
              final cx = (x * stride).toDouble();
              final cy = (y * stride).toDouble();
              final bb = b[n];
              detScores.add(score);
              detBoxes.add([
                (cx - bb[0] * stride) / scale,
                (cy - bb[1] * stride) / scale,
                (cx + bb[2] * stride) / scale,
                (cy + bb[3] * stride) / scale,
              ]);
              final kk = k[n];
              detKps.add([
                [(cx + kk[0] * stride) / scale, (cy + kk[1] * stride) / scale],
                [(cx + kk[2] * stride) / scale, (cy + kk[3] * stride) / scale],
                [(cx + kk[4] * stride) / scale, (cy + kk[5] * stride) / scale],
                [(cx + kk[6] * stride) / scale, (cy + kk[7] * stride) / scale],
                [(cx + kk[8] * stride) / scale, (cy + kk[9] * stride) / scale],
              ]);
            }
            n++;
          }
        }
      }
    }
    if (detScores.isEmpty) return const [];
    // Stable sort, descending score (mirrors np.argsort(-s, stable)).
    final order = List<int>.generate(detScores.length, (i) => i)
      ..sort((a, b) => detScores[b].compareTo(detScores[a]));
    final boxes = [for (final i in order) [...detBoxes[i], detScores[i]]];
    final keep = _nms(boxes);
    return [
      for (final k in keep)
        FaceDetection(
          score: boxes[k][4],
          bbox: boxes[k].sublist(0, 4),
          kps: detKps[order[k]],
        ),
    ];
  }

  /// Greedy NMS on `[x1,y1,x2,y2,score]` rows (+1 areas, stable order).
  static List<int> _nms(List<List<double>> dets) {
    final keep = <int>[];
    var order = List<int>.generate(dets.length, (i) => i);
    final areas = [
      for (final d in dets) (d[2] - d[0] + 1) * (d[3] - d[1] + 1)
    ];
    while (order.isNotEmpty) {
      final i = order.first;
      keep.add(i);
      final rest = <int>[];
      for (var j = 1; j < order.length; j++) {
        final o = order[j];
        final xx1 = max(dets[i][0], dets[o][0]);
        final yy1 = max(dets[i][1], dets[o][1]);
        final xx2 = min(dets[i][2], dets[o][2]);
        final yy2 = min(dets[i][3], dets[o][3]);
        final w = max(0.0, xx2 - xx1 + 1);
        final h = max(0.0, yy2 - yy1 + 1);
        final ovr =
            (w * h) / (areas[i] + areas[o] - w * h);
        if (ovr <= nmsThresh) rest.add(o);
      }
      order = rest;
    }
    return keep;
  }

  /// Largest-area detection (backend picks the largest face).
  static FaceDetection? largest(List<FaceDetection> dets) {
    if (dets.isEmpty) return null;
    var best = dets.first;
    var bestArea = -1.0;
    for (final d in dets) {
      final area =
          (d.bbox[2] - d.bbox[0]) * (d.bbox[3] - d.bbox[1]);
      if (area > bestArea) {
        bestArea = area;
        best = d;
      }
    }
    return best;
  }
}

// ------------------------------------------------------------------ Align

/// ArcFace 112×112 landmark template (insightface `face_align.py`).
const arcfaceDst = [
  [38.2946, 51.6963],
  [73.5318, 51.5014],
  [56.0252, 71.7366],
  [41.5493, 92.3655],
  [70.7299, 92.2041],
];

/// Similarity alignment port (`estimate_norm` + `warpAffine`, bilinear,
/// border 0).
class FaceAlign {
  /// Least-squares similarity `M = [[a,-b,tx],[b,a,ty]]` mapping `lmk`
  /// onto [arcfaceDst]. Returns `[a, b, tx, ty]`.
  static List<double> estimateNorm(List<List<double>> lmk) {
    // Normal equations for 4 unknowns over 10 rows.
    final ata = List.generate(4, (_) => List.filled(4, 0.0));
    final atb = List.filled(4, 0.0);
    for (var i = 0; i < 5; i++) {
      final sx = lmk[i][0], sy = lmk[i][1];
      final dx = arcfaceDst[i][0], dy = arcfaceDst[i][1];
      final rows = [
        [sx, -sy, 1.0, 0.0],
        [sy, sx, 0.0, 1.0],
      ];
      final rhs = [dx, dy];
      for (var r = 0; r < 2; r++) {
        for (var c1 = 0; c1 < 4; c1++) {
          atb[c1] += rows[r][c1] * rhs[r];
          for (var c2 = 0; c2 < 4; c2++) {
            ata[c1][c2] += rows[r][c1] * rows[r][c2];
          }
        }
      }
    }
    return _solve4(ata, atb);
  }

  static List<double> _solve4(List<List<double>> a, List<double> b) {
    final m = [for (final row in a) [...row, 0.0]];
    for (var i = 0; i < 4; i++) {
      m[i][4] = b[i];
    }
    for (var col = 0; col < 4; col++) {
      var piv = col;
      for (var row = col + 1; row < 4; row++) {
        if (m[row][col].abs() > m[piv][col].abs()) piv = row;
      }
      final tmp = m[col];
      m[col] = m[piv];
      m[piv] = tmp;
      final div = m[col][col];
      for (var k = col; k < 5; k++) {
        m[col][k] /= div;
      }
      for (var row = 0; row < 4; row++) {
        if (row == col) continue;
        final f = m[row][col];
        for (var k = col; k < 5; k++) {
          m[row][k] -= f * m[col][k];
        }
      }
    }
    return [m[0][4], m[1][4], m[2][4], m[3][4]];
  }

  /// Warps `src` into `size`×`size` via inverse-mapped bilinear sampling,
  /// out-of-bounds → 0 (mirrors `cv2.warpAffine(..., borderValue=0)`).
  /// `abtt` = `[a, b, tx, ty]` from [estimateNorm].
  static RgbImage warp(RgbImage src, List<double> abtt, int size) {
    final a = abtt[0], b = abtt[1], tx = abtt[2], ty = abtt[3];
    final det = a * a + b * b;
    final out = Uint8List(size * size * 3);
    var o = 0;
    for (var v = 0; v < size; v++) {
      for (var u = 0; u < size; u++) {
        final sx = (a * (u - tx) + b * (v - ty)) / det;
        final sy = (-b * (u - tx) + a * (v - ty)) / det;
        for (var c = 0; c < 3; c++) {
          out[o++] = _bilinear(src, sx, sy, c);
        }
      }
    }
    return RgbImage(size, size, out);
  }

  /// 112×112 alignment warp used before the recognition model.
  static RgbImage warp112(RgbImage src, List<double> abtt) =>
      warp(src, abtt, 112);

  static int _bilinear(RgbImage src, double x, double y, int c) {
    final x0 = x.floor(), y0 = y.floor();
    final fx = x - x0, fy = y - y0;
    double sample(int xx, int yy) {
      if (xx < 0 || yy < 0 || xx >= src.width || yy >= src.height) return 0;
      return src.at(xx, yy, c);
    }

    final v = sample(x0, y0) * (1 - fx) * (1 - fy) +
        sample(x0 + 1, y0) * fx * (1 - fy) +
        sample(x0, y0 + 1) * (1 - fx) * fy +
        sample(x0 + 1, y0 + 1) * fx * fy;
    return v.round().clamp(0, 255);
  }
}

// ------------------------------------------------------------------ Blobs

class DetInput {
  const DetInput(this.blob, this.scale);

  /// NCHW float32 `[1,3,640,640]`, `(rgb-127.5)/128`.
  final Float32List blob;

  /// Letterboxed height / original height.
  final double scale;
}

class BlobPrep {
  /// Letterbox-fit (long side → 640, zero-pad) + normalize.
  /// Mirrors `SCRFD._detect_candidates` + `blobFromImage`.
  static DetInput detBlob(RgbImage src) {
    const size = ScrfdDecoder.detSize;
    final scale = size / max(src.width, src.height);
    // Truncate like Python int()/cv2 dsize (NOT round): off-by-one here
    // shifts the whole detector letterbox.
    final nw = (src.width * scale).toInt();
    final nh = (src.height * scale).toInt();
    final resized = _resizeBilinear(src, nw, nh);
    final blob = Float32List(1 * 3 * size * size);
    for (var y = 0; y < size; y++) {
      for (var x = 0; x < size; x++) {
        double r = 0, g = 0, bl = 0;
        if (x < nw && y < nh) {
          r = resized.at(x, y, 0);
          g = resized.at(x, y, 1);
          bl = resized.at(x, y, 2);
        }
        final i = y * size + x;
        blob[i] = (r - 127.5) / 128.0;
        blob[size * size + i] = (g - 127.5) / 128.0;
        blob[2 * size * size + i] = (bl - 127.5) / 128.0;
      }
    }
    return DetInput(blob, nh / src.height);
  }

  /// `(rgb-127.5)/127.5` NCHW `[1,3,112,112]`. Mirrors `ArcFaceONNX`.
  static Float32List recBlob(RgbImage aligned112) {
    assert(aligned112.width == 112 && aligned112.height == 112);
    final blob = Float32List(1 * 3 * 112 * 112);
    for (var y = 0; y < 112; y++) {
      for (var x = 0; x < 112; x++) {
        final i = y * 112 + x;
        blob[i] = (aligned112.at(x, y, 0) - 127.5) / 127.5;
        blob[112 * 112 + i] = (aligned112.at(x, y, 1) - 127.5) / 127.5;
        blob[2 * 112 * 112 + i] = (aligned112.at(x, y, 2) - 127.5) / 127.5;
      }
    }
    return blob;
  }

  static RgbImage _resizeBilinear(RgbImage src, int nw, int nh) {
    final out = Uint8List(nw * nh * 3);
    var o = 0;
    for (var y = 0; y < nh; y++) {
      for (var x = 0; x < nw; x++) {
        final sx = (x + 0.5) * src.width / nw - 0.5;
        final sy = (y + 0.5) * src.height / nh - 0.5;
        for (var c = 0; c < 3; c++) {
          out[o++] = FaceAlign._bilinear(src, sx, sy, c);
        }
      }
    }
    return RgbImage(nw, nh, out);
  }

  static List<double> l2norm(List<double> v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    final n = sqrt(s);
    return [for (final x in v) x / n];
  }
}

// ------------------------------------------------------------------ Engine

/// Thin onnxruntime glue over the pure pipeline above.
class OrtFaceEngine {
  OrtFaceEngine._(this._det, this._rec);

  final OrtSession _det;
  final OrtSession _rec;

  static bool _envReady = false;

  static Future<OrtFaceEngine> open(FaceModelPack pack) async {
    if (!await pack.isReady()) {
      throw ModelPackMissing(await pack.missingBytes());
    }
    if (!_envReady) {
      OrtEnv.instance.init();
      _envReady = true;
    }
    final detBytes =
        await pack.det.readAsBytes().then((b) => Uint8List.fromList(b));
    final recBytes =
        await pack.rec.readAsBytes().then((b) => Uint8List.fromList(b));
    final opts = OrtSessionOptions();
    final det = OrtSession.fromBuffer(detBytes, opts);
    final rec = OrtSession.fromBuffer(recBytes, opts);
    return OrtFaceEngine._(det, rec);
  }

  void release() {
    _det.release();
    _rec.release();
  }

  Future<FaceDetection?> largestFace(RgbImage src) async {
    final input = BlobPrep.detBlob(src);
    final tensor = OrtValueTensor.createTensorWithDataList(
        input.blob, [1, 3, 640, 640]);
    final run = OrtRunOptions();
    try {
      final outs = await _det.runAsync(run, {'input.1': tensor});
      if (outs == null || outs.length < 9) return null;
      List<List<double>> mat(OrtValue? v) =>
          (v?.value as List).map((r) => (r as List)
              .map((e) => (e as num).toDouble())
              .toList()).toList();

      final scores = [mat(outs[0]), mat(outs[1]), mat(outs[2])];
      final boxes = [mat(outs[3]), mat(outs[4]), mat(outs[5])];
      final kpss = [mat(outs[6]), mat(outs[7]), mat(outs[8])];
      final dets = ScrfdDecoder.decode(
        scores: scores,
        bboxes: boxes,
        kpss: kpss,
        scale: input.scale,
      );
      return ScrfdDecoder.largest(dets);
    } finally {
      tensor.release();
      run.release();
    }
  }

  /// 512-d L2-normalized embedding of the largest face in `jpeg`.
  /// Returns null when no face is detected.
  Future<List<double>?> embedJpeg(Uint8List jpeg) async {
    final src = RgbImage.decode(jpeg);
    final face = await largestFace(src);
    if (face == null) return null;
    final abtt = FaceAlign.estimateNorm(face.kps);
    final aligned = FaceAlign.warp112(src, abtt);
    final blob = BlobPrep.recBlob(aligned);
    final tensor = OrtValueTensor.createTensorWithDataList(
        blob, [1, 3, 112, 112]);
    final run = OrtRunOptions();
    try {
      final outs = await _rec.runAsync(run, {'input.1': tensor});
      if (outs == null || outs.isEmpty) return null;
      final rows = outs[0]?.value as List;
      final flat = (rows.first as List)
          .map((e) => (e as num).toDouble())
          .toList();
      return BlobPrep.l2norm(flat);
    } finally {
      tensor.release();
      run.release();
    }
  }
}
