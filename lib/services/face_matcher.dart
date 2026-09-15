import 'dart:math';
import 'dart:typed_data';

import 'face_embedder.dart';
import 'face_model_pack.dart';
import 'face_projection.dart';
import 'mosip.dart';

/// Face "same or not" check: live selfie vs the face reference in the QR.
///
/// Fully on-device: SCRFD detection + ArcFace embedding (buffalo_l,
/// same pipeline as the backend `scripts/facematch.py`) compared against
/// the QR's irreversible hash/template.
///
/// Thresholds: [hashThreshold] defaults to **0.60** — tightened from the
/// backend lab default (0.55) after field data showed strangers scoring
/// above 0.55 while genuine matches score ~0.79. Template threshold
/// stays 0.30 (different score scale). Both are tunable at runtime
/// (scanner screen) and [hashThreshold] persists via shared_preferences;
/// keep the backend aligned with `FACE_MATCH_THRESHOLD` in its `.env`
/// for online parity.
///
/// The model pack (~191MB) downloads once on first use
/// ([FaceModelPack]); [matchSelfieVsQr] throws [ModelPackMissing] until
/// it is cached.
class FaceMatcher {
  static double hashThreshold = 0.60;
  static const templateThreshold = 0.30;
  static const backend = 'insightface-buffalo_l (on-device)';

  static OrtFaceEngine? _engine;

  /// Scores a live selfie against the QR credential. Throws
  /// [ModelPackMissing] when the model pack needs downloading first.
  ///
  /// NOTE: inference runs on the calling isolate (a few seconds on
  /// mid-range phones — the UI shows a busy state). A future improvement
  /// is opening a second engine inside a background isolate.
  Future<FaceMatchResult> matchSelfieVsQr({
    required Uint8List selfieBytes,
    required MosipCredential credential,
    FaceModelPack? pack,
    OrtFaceEngine? engine,
  }) async {
    if (selfieBytes.isEmpty) {
      return const FaceMatchResult(
        FaceMatchStatus.noFace,
        detail: 'Empty selfie — capture again.',
      );
    }
    final eng = engine ?? await _sharedEngine(pack);
    final emb = await eng.embedJpeg(selfieBytes);
    if (emb == null) {
      return const FaceMatchResult(
        FaceMatchStatus.noFace,
        detail: 'No face detected — face the camera in good light and retry.',
      );
    }
    final isTemplate =
        credential.faceHash.length == 132 && credential.faceHash[0] == 0x02;
    final threshold = isTemplate ? templateThreshold : hashThreshold;
    final score = isTemplate
        ? scoreTemplate(credential.faceHash, FaceProjection.project(emb))
        : scoreHash(credential.faceHash, emb);
    if (score >= threshold) {
      return FaceMatchResult(FaceMatchStatus.match,
          score: score, threshold: threshold, backend: backend);
    }
    return FaceMatchResult(FaceMatchStatus.mismatch,
        score: score,
        threshold: threshold,
        backend: backend,
        detail: 'Score below threshold — not the same person.');
  }

  /// Shared process-wide engine (sessions weigh ~190MB; opened once).
  /// Throws [ModelPackMissing] when the pack needs downloading first —
  /// the UI catches this and offers the one-time download.
  static Future<OrtFaceEngine> _sharedEngine(FaceModelPack? pack) async {
    final existing = _engine;
    if (existing != null) return existing;
    final p = pack ?? await FaceModelPack.system();
    final engine = await OrtFaceEngine.open(p);
    _engine = engine;
    return engine;
  }

  /// Visible for tests.
  static void resetEngineForTest() {
    _engine?.release();
    _engine = null;
  }

  /// `1 - hamming fraction` between a stored 65B hash (`0x01` + 512 sign
  /// bits, MSB-first) and a 512-d live embedding. Port of
  /// `InsightFaceMatcher.match_hash`.
  static double scoreHash(Uint8List hash, List<double> liveEmbedding) {
    if (hash.length != 65 || hash[0] != 0x01) {
      throw const FormatException('unsupported face-hash version');
    }
    if (liveEmbedding.length != 512) {
      throw const FormatException('embedding must be 512-d');
    }
    var diff = 0;
    for (var i = 0; i < 512; i++) {
      final storedBit = (hash[1 + (i ~/ 8)] >> (7 - (i % 8))) & 1;
      final liveBit = liveEmbedding[i] > 0 ? 1 : 0;
      if (storedBit != liveBit) diff++;
    }
    return 1.0 - diff / 512.0;
  }

  /// Cosine similarity between a stored 132B template
  /// (`02 01 80 7f` + 128 int8 quantized, /127) and a 128-d normalized
  /// live projection. Port of `InsightFaceMatcher.match_template`
  /// (projection itself — seed 39794 — lives with the embedder).
  static double scoreTemplate(Uint8List template, List<double> liveProjected) {
    if (template.length != 132 ||
        template[0] != 0x02 ||
        template[1] != 0x01 ||
        template[2] != 0x80 ||
        template[3] != 0x7f) {
      throw const FormatException('unsupported face template');
    }
    if (liveProjected.length != 128) {
      throw const FormatException('projection must be 128-d');
    }
    final stored = List<double>.generate(
        128, (i) => (template[4 + i] >= 128 ? template[4 + i] - 256 : template[4 + i]) / 127.0);
    final storedNorm = _norm(stored);
    final liveNorm = _norm(liveProjected);
    var dot = 0.0;
    for (var i = 0; i < 128; i++) {
      dot += (stored[i] / storedNorm) * (liveProjected[i] / liveNorm);
    }
    return dot.clamp(-1.0, 1.0);
  }

  static double _norm(List<double> v) {
    var s = 0.0;
    for (final x in v) {
      s += x * x;
    }
    final n = sqrt(s);
    if (n == 0 || !n.isFinite) throw const FormatException('zero vector');
    return n;
  }
}

enum FaceMatchStatus {
  /// Live embedding matched the QR reference at/above threshold.
  match,

  /// Scored below threshold.
  mismatch,

  /// No face in the selfie.
  noFace,
}

class FaceMatchResult {
  const FaceMatchResult(this.status,
      {this.score, this.threshold, this.backend, this.detail});

  final FaceMatchStatus status;
  final double? score;
  final double? threshold;
  final String? backend;
  final String? detail;

  bool get isMatch => status == FaceMatchStatus.match;
}
