import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'face_projection_data.dart';

/// The stable v1 random orthogonal map (seed 39794, 128×512,
/// row-normalized) — exact port of `InsightFaceMatcher._project` in
/// `scripts/facematch.py`. The matrix is fixed, so it ships as data
/// ([face_projection_data.dart], generated once with numpy) instead of
/// reimplementing numpy's PCG64+ziggurat stream in Dart.
class FaceProjection {
  static Float32List? _matrix;

  static Float32List matrix() {
    final cached = _matrix;
    if (cached != null) return cached;
    final bytes = base64.decode(kProjectionB64.replaceAll('\n', ''));
    final m = Float32List.view(bytes.buffer);
    assert(m.length == 128 * 512);
    _matrix = m;
    return m;
  }

  /// Projects a 512-d embedding to a normalized 128-d vector.
  static List<double> project(List<double> embedding) {
    if (embedding.length != 512) {
      throw const FormatException('embedding must be 512-d');
    }
    final m = matrix();
    final out = List<double>.filled(128, 0.0);
    for (var r = 0; r < 128; r++) {
      var s = 0.0;
      final base = r * 512;
      for (var c = 0; c < 512; c++) {
        s += m[base + c] * embedding[c];
      }
      out[r] = s;
    }
    var norm = 0.0;
    for (final v in out) {
      norm += v * v;
    }
    norm = sqrt(norm);
    if (norm == 0 || !norm.isFinite) {
      throw const FormatException('invalid projected embedding');
    }
    return [for (final v in out) v / norm];
  }
}
