import 'dart:math';
import 'dart:typed_data';

import 'face_embedder.dart';
import 'face_model_pack.dart';
import 'face_projection.dart';
import 'mosip.dart';

/// Face "same or not" check: live selfie vs the face reference in the QR.
///
/// Fully on-device: SCRFD-500M detection + dual recognition embeddings
/// (EdgeFace-S for current QRs, buffalo w600k_mbf for legacy QRs — same
/// pipeline as the backend `scripts/facematch.py`, `FACE_MATCHER=edgeface`
/// with `insightface-buffalo_s` history) compared against the QR's
/// irreversible hash/template.
///
/// Old templates carry no model id (identical 68B/132B containers in both
/// eras), so each selfie is embedded in **both** spaces and the better
/// margin-above-threshold wins ([pickMatch]). A buffalo-issued QR verified
/// with an EdgeFace-only build scores garbage (proven: same person 0.74
/// same-space vs 0.08 cross-space) — dual embedding is what makes old QRs
/// verify.
///
/// Thresholds: [hashThreshold] defaults to **0.60** (legacy 65B sign-hash
/// path, both spaces). [templateThreshold] defaults to **0.40** —
/// calibrated Sep 2026 for EdgeFace-S (genuine >= 0.73, impostors <= 0.13
/// on both the 132B v2 and 68B v3-64 template paths).
/// [legacyTemplateThreshold] defaults to **0.35** — calibrated Sep 2026
/// for w600k_mbf (genuine >= 0.61, impostors <= 0.16). [hashThreshold] is
/// tunable at runtime (scanner screen) and persists via
/// shared_preferences; keep the backend aligned with
/// `FACE_TEMPLATE_MATCH_THRESHOLD` in its `.env` for online parity.
///
/// The model pack (~31MB) downloads once on first use
/// ([FaceModelPack]); [matchSelfieVsQr] throws [ModelPackMissing] until
/// it is cached.
class FaceMatcher {
  static double hashThreshold = 0.60;
  static const templateThreshold = 0.40;
  static const legacyTemplateThreshold = 0.35;
  static const backend = 'edgeface-s (on-device)';
  static const legacyBackend = 'buffalo-mbf (on-device · legacy QR)';

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
    final both = await eng.embedJpegBoth(selfieBytes);
    if (both == null) {
      return const FaceMatchResult(
        FaceMatchStatus.noFace,
        detail: 'No face detected — face the camera in good light and retry.',
      );
    }
    final verdict = pickMatch(
      edgeScore: _scoreCredential(credential.faceHash, both.edge),
      legacyScore: _scoreCredential(credential.faceHash, both.legacy),
      isTemplate: _isTemplate(credential.faceHash),
    );
    if (verdict.match) {
      return FaceMatchResult(FaceMatchStatus.match,
          score: verdict.score,
          threshold: verdict.threshold,
          backend: verdict.backend);
    }
    return FaceMatchResult(FaceMatchStatus.mismatch,
        score: verdict.score,
        threshold: verdict.threshold,
        backend: verdict.backend,
        detail: 'Score below threshold — not the same person.');
  }

  /// True for versioned compact templates (132B v2 / 68B v3-64); anything
  /// else takes the legacy 65B sign-hash path.
  static bool _isTemplate(Uint8List faceHash) =>
      (faceHash.length == 132 && faceHash[0] == 0x02) ||
      (faceHash.length == 68 && faceHash[0] == 0x03);

  /// Scores `faceHash` against a 512-d live embedding in one space,
  /// routing by header (v3-64 → 64-d projection, v2 → 128-d projection,
  /// else sign-hash). Throws [FormatException] on unknown formats.
  static double _scoreCredential(Uint8List faceHash, List<double> emb) {
    if (faceHash.length == 68 && faceHash[0] == 0x03) {
      return scoreTemplateV3(faceHash, FaceProjection.project64(emb));
    }
    if (faceHash.length == 132 && faceHash[0] == 0x02) {
      return scoreTemplate(faceHash, FaceProjection.project(emb));
    }
    return scoreHash(faceHash, emb);
  }

  /// Picks the winning embedding space by margin above its own threshold.
  /// Pure and unit-tested. `isTemplate` selects template vs hash
  /// thresholds per space. The reported score/threshold always belong to
  /// the winning space, so the UI shows a coherent pair.
  static ({double score, double threshold, String backend, bool match})
      pickMatch({
    required double edgeScore,
    required double legacyScore,
    required bool isTemplate,
  }) {
    final edgeThreshold = isTemplate ? templateThreshold : hashThreshold;
    final legacyThreshold =
        isTemplate ? legacyTemplateThreshold : hashThreshold;
    final edgeMargin = edgeScore - edgeThreshold;
    final legacyMargin = legacyScore - legacyThreshold;
    if (edgeMargin >= legacyMargin) {
      return (
        score: edgeScore,
        threshold: edgeThreshold,
        backend: backend,
        match: edgeMargin >= 0
      );
    }
    return (
      score: legacyScore,
      threshold: legacyThreshold,
      backend: legacyBackend,
      match: legacyMargin >= 0
    );
  }

  /// Shared process-wide engine (sessions weigh ~60MB; opened once).
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

  /// Cosine similarity between a stored 68B v3-64 template
  /// (`03 02 40 7f` + 64 int8 quantized, /127 — the backend default) and
  /// a 64-d normalized live projection ([FaceProjection.project64]).
  static double scoreTemplateV3(
      Uint8List template, List<double> liveProjected) {
    if (template.length != 68 ||
        template[0] != 0x03 ||
        template[1] != 0x02 ||
        template[2] != 0x40 ||
        template[3] != 0x7f) {
      throw const FormatException('unsupported face template v3');
    }
    if (liveProjected.length != 64) {
      throw const FormatException('projection must be 64-d');
    }
    final stored = List<double>.generate(
        64, (i) => (template[4 + i] >= 128 ? template[4 + i] - 256 : template[4 + i]) / 127.0);
    final storedNorm = _norm(stored);
    final liveNorm = _norm(liveProjected);
    var dot = 0.0;
    for (var i = 0; i < 64; i++) {
      dot += (stored[i] / storedNorm) * (liveProjected[i] / liveNorm);
    }
    return dot.clamp(-1.0, 1.0);
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
