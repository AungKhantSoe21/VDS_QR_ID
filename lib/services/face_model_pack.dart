import 'dart:async';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:path_provider/path_provider.dart';

/// On-device face-model pack (InsightFace buffalo_l weights).
///
/// NOT bundled (det 17MB + rec 174MB would bloat the APK and the repo).
/// Downloaded once on first face verification from HuggingFace (immutable
/// file URLs), SHA256-verified against the official buffalo_l release
/// (`deepinsight/insightface v0.7`), then cached in the app support dir.
///
/// Fully offline afterwards — no server involved.
class FaceModelPack {
  static const detFile = 'det_10g.onnx';
  static const recFile = 'w600k_r50.onnx';

  static const _detUrl =
      'https://huggingface.co/immich-app/buffalo_l/resolve/main/detection/model.onnx';
  static const _recUrl =
      'https://huggingface.co/immich-app/buffalo_l/resolve/main/recognition/model.onnx';

  /// SHA256 of the official buffalo_l release files (verified Sep 2026).
  static const detSha256 =
      '5838f7fe053675b1c7a08b633df49e7af5495cee0493c7dcf6697200b85b5b91';
  static const recSha256 =
      '4c06341c33c2ca1f86781dab0e829f88ad5b64be9fba56e56bc9ebdefc619e43';

  static const detBytes = 16923827;
  static const recBytes = 174383860;

  static int get totalBytes => detBytes + recBytes;

  final Directory baseDir;

  FaceModelPack(this.baseDir);

  static Future<FaceModelPack> system() async {
    final support = await getApplicationSupportDirectory();
    final dir = Directory('${support.path}/face_models');
    if (!await dir.exists()) await dir.create(recursive: true);
    return FaceModelPack(dir);
  }

  File get det => File('${baseDir.path}/$detFile');
  File get rec => File('${baseDir.path}/$recFile');

  Future<bool> _valid(File f, String sha) async {
    if (!await f.exists()) return false;
    if (await f.length() == 0) return false;
    return await _sha256File(f) == sha;
  }

  static Future<String> _sha256File(File f) async {
    final sink = Sha256().newHashSink();
    await for (final chunk in f.openRead()) {
      sink.add(chunk);
    }
    sink.close();
    final hash = await sink.hash();
    return hash.bytes
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  /// True when both models are cached and hash-verified.
  Future<bool> isReady() async =>
      await _valid(det, detSha256) && await _valid(rec, recSha256);

  /// Deletes cached model files (frees ~191MB). Next verification
  /// re-downloads them.
  Future<void> clear() async {
    for (final f in [det, rec, File('${det.path}.part'), File('${rec.path}.part')]) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Bytes still missing (for UI messaging).
  Future<int> missingBytes() async {
    var missing = 0;
    if (!await _valid(det, detSha256)) missing += detBytes;
    if (!await _valid(rec, recSha256)) missing += recBytes;
    return missing;
  }

  /// Downloads missing files with progress reports (`downloaded/total`
  /// bytes, both files combined). Throws on hash mismatch or network
  /// failure; partial files are deleted so the next run retries cleanly.
  Future<void> ensureReady({
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (await isReady()) {
      onProgress?.call(totalBytes, totalBytes);
      return;
    }
    var done = 0;
    if (await _valid(det, detSha256)) done += detBytes;
    if (await _valid(rec, recSha256)) done += recBytes;
    if (!await _valid(det, detSha256)) {
      done += await _fetch(_detUrl, det, detSha256, detBytes,
          (n) => onProgress?.call(done + n, totalBytes));
    }
    if (!await _valid(rec, recSha256)) {
      done += await _fetch(_recUrl, rec, recSha256, recBytes,
          (n) => onProgress?.call(done + n, totalBytes));
    }
  }

  static Future<int> _fetch(
    String url,
    File dest,
    String sha,
    int expectedBytes,
    void Function(int downloadedFileBytes) onFileProgress,
  ) async {
    final tmp = File('${dest.path}.part');
    if (await tmp.exists()) await tmp.delete();
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      final res = await req.close();
      if (res.statusCode != 200) {
        throw HttpException('Model download failed: HTTP ${res.statusCode}');
      }
      final sink = tmp.openWrite();
      var n = 0;
      await for (final chunk in res) {
        sink.add(chunk);
        n += chunk.length;
        onFileProgress(n);
      }
      await sink.close();
      if (n != expectedBytes) {
        throw HttpException(
            'Model size mismatch ($n vs $expectedBytes bytes)');
      }
      if (await _sha256File(tmp) != sha) {
        throw const FormatException('Model SHA256 mismatch — not official weights');
      }
      await tmp.rename(dest.path);
      return n;
    } finally {
      client.close();
      if (await tmp.exists()) {
        try {
          await tmp.delete();
        } catch (_) {}
      }
    }
  }
}

/// Thrown when the face-model pack is missing and must be downloaded first.
class ModelPackMissing implements Exception {
  const ModelPackMissing(this.missingBytes);
  final int missingBytes;

  String get message =>
      'Face-model pack not on device (~${(missingBytes / 1048576).ceil()} MB download on first use).';
}
