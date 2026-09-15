import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';

/// One cached model file: bundled fp32 asset (primary, offline) with an
/// identical fp32 download fallback (same bytes, same SHA).
class _ModelSlot {
  const _ModelSlot({
    required this.fileName,
    required this.assetPath,
    required this.assetSha,
    required this.assetBytes,
    required this.urls,
    required this.downloadSha,
    required this.downloadBytes,
  });

  final String fileName;
  final String assetPath;
  final String assetSha;
  final int assetBytes;
  final List<String> urls;
  final String downloadSha;
  final int downloadBytes;
}

/// On-device face-model pack: SCRFD-500M detector (shared) + two
/// recognition embeddings.
///
/// - EdgeFace-S (current QRs, Sep 2026+).
/// - ArcFace w600k_mbf (legacy buffalo QRs). Old templates carry no model
///   id (same 68B/132B containers), so the matcher tries both embedding
///   spaces with per-model thresholds.
///
/// **Bundled**: fp32 weights (~31MB) ship in the APK under
/// `assets/models/` and are copied to the app support dir on first use —
/// no network needed. fp32 is used deliberately: the on-device
/// onnxruntime build has no `ConvInteger` kernel, so int8-quantized
/// models fail to load on phones (code=9). If a bundled asset is
/// missing/corrupt, the pack falls back to downloading the identical
/// official weights (SHA-verified) with resume + mirror retries.
///
/// Fully offline after first setup — no server involved.
///
/// v4 (bundled int8, Sep 2026) replaces the v3 download-on-first-use pack.
/// Cache filenames are unchanged, so a v3 cache is reused as-is; use
/// [clear] to reclaim space (next setup re-copies from the bundle).
class FaceModelPack {
  static const detFile = 'det_500m.onnx';
  static const recFile = 'edgeface_s.onnx';
  static const legacyRecFile = 'w600k_mbf.onnx';

  static const _slots = [
    _ModelSlot(
      fileName: detFile,
      assetPath: 'assets/models/det_500m.onnx',
      assetSha:
          '5e4447f50245bbd7966bd6c0fa52938c61474a04ec7def48753668a9d8b4ea3a',
      assetBytes: 2524817,
      urls: [
        'https://huggingface.co/yakhyo/uniface-weights/resolve/4c7ed723a20deb7ff154b1ba7d6e73747d954016/scrfd_500m.onnx',
      ],
      downloadSha:
          '5e4447f50245bbd7966bd6c0fa52938c61474a04ec7def48753668a9d8b4ea3a',
      downloadBytes: 2524817,
    ),
    _ModelSlot(
      fileName: recFile,
      assetPath: 'assets/models/edgeface_s.onnx',
      assetSha:
          'b850767cf791bda585600b5c4c7d7432b2f998ccd862caae34ef1afa967d2e54',
      assetBytes: 14805514,
      urls: [
        'https://github.com/yakhyo/edgeface-onnx/releases/download/weights/edgeface_s_gamma_05.onnx',
        // HF mirror of the same file (fallback when GitHub is slow).
        'https://huggingface.co/yakhyo/uniface-weights/resolve/4c7ed723a20deb7ff154b1ba7d6e73747d954016/edgeface_s_gamma_05.onnx',
      ],
      downloadSha:
          'b850767cf791bda585600b5c4c7d7432b2f998ccd862caae34ef1afa967d2e54',
      downloadBytes: 14805514,
    ),
    _ModelSlot(
      fileName: legacyRecFile,
      assetPath: 'assets/models/w600k_mbf.onnx',
      assetSha:
          '9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f',
      assetBytes: 13616099,
      urls: [
        'https://huggingface.co/immich-app/buffalo_s/resolve/main/recognition/model.onnx',
      ],
      downloadSha:
          '9cc6e4a75f0e2bf0b1aed94578f144d15175f357bdc05e815e5c4a02b319eb4f',
      downloadBytes: 13616099,
    ),
  ];

  /// Bundled-asset SHAs (primary identity of each cache file; identical
  /// to the download SHAs since both are the official fp32 weights).
  static String get detSha256 => _slots[0].assetSha;
  static String get recSha256 => _slots[1].assetSha;
  static String get legacyRecSha256 => _slots[2].assetSha;

  static int get detBytes => _slots[0].assetBytes;
  static int get recBytes => _slots[1].assetBytes;
  static int get legacyRecBytes => _slots[2].assetBytes;

  static int get totalBytes =>
      _slots.fold(0, (sum, s) => sum + s.assetBytes);

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
  File get legacyRec => File('${baseDir.path}/$legacyRecFile');

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

  /// True when all models are cached and hash-verified (bundled int8
  /// or fallback fp32 bytes both accepted).
  Future<bool> isReady() async {
    for (final s in _slots) {
      final f = File('${baseDir.path}/${s.fileName}');
      if (!await _valid(f, s.assetSha) &&
          !await _valid(f, s.downloadSha)) {
        return false;
      }
    }
    return true;
  }

  /// Deletes cached model files (frees ~31MB, plus any abandoned packs).
  /// Next setup re-copies from the bundle — offline, in seconds.
  Future<void> clear() async {
    final garbage = <File>[
      for (final s in _slots) ...[
        File('${baseDir.path}/${s.fileName}'),
        File('${baseDir.path}/${s.fileName}.part'),
      ],
      // Abandoned v1 filenames (Sep 2026 model swap).
      File('${baseDir.path}/det_10g.onnx'),
      File('${baseDir.path}/w600k_r50.onnx'),
    ];
    for (final f in garbage) {
      try {
        if (await f.exists()) await f.delete();
      } catch (_) {}
    }
  }

  /// Bytes still missing (for UI messaging).
  Future<int> missingBytes() async {
    var missing = 0;
    for (final s in _slots) {
      final f = File('${baseDir.path}/${s.fileName}');
      if (!await _valid(f, s.assetSha) &&
          !await _valid(f, s.downloadSha)) {
        missing += s.assetBytes;
      }
    }
    return missing;
  }

  /// First-time setup with progress reports (`done/total` bytes).
  /// Copies missing files from the APK bundle (offline, seconds);
  /// falls back to fp32 download with resume + mirror retries when a
  /// bundled asset is missing or corrupt. Throws when both fail.
  Future<void> ensureReady({
    void Function(int downloaded, int total)? onProgress,
  }) async {
    if (await isReady()) {
      onProgress?.call(totalBytes, totalBytes);
      return;
    }
    var done = 0;
    void report(int fileDone) =>
        onProgress?.call(min(done + fileDone, totalBytes), totalBytes);
    for (final s in _slots) {
      final dest = File('${baseDir.path}/${s.fileName}');
      done += await _ensureSlot(s, dest, report);
      onProgress?.call(min(done, totalBytes), totalBytes);
    }
  }

  /// Installs one slot: reuse if valid, else bundle copy, else download.
  /// Returns the installed file size.
  Future<int> _ensureSlot(_ModelSlot s, File dest,
      void Function(int fileDone) report) async {
    if (await _valid(dest, s.assetSha)) return s.assetBytes;
    if (await _valid(dest, s.downloadSha)) {
      return dest.length();
    }
    try {
      final data = await rootBundle.load(s.assetPath);
      await dest.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (await _sha256File(dest) == s.assetSha) {
        report(s.assetBytes);
        return s.assetBytes;
      }
      try {
        await dest.delete();
      } catch (_) {}
    } catch (_) {
      // No bundle asset (dev/test) — fall through to download.
    }
    return _fetch(s.urls, dest, s.downloadSha, s.downloadBytes, report);
  }

  /// Test seam over [_fetch] (mirrors, retries, resume). Not for app use.
  @visibleForTesting
  static Future<int> fetchForTest({
    required List<String> urls,
    required File dest,
    required String sha,
    required int expectedBytes,
    required void Function(int downloadedFileBytes) onFileProgress,
  }) =>
      _fetch(urls, dest, sha, expectedBytes, onFileProgress);

  /// Downloads one model file, trying mirrors in order with retries.
  ///
  /// Slow/flaky-link behavior (the reason this exists): partial `.part`
  /// files are **resumed** via HTTP Range instead of restarted, each
  /// mirror gets up to 3 attempts with backoff, and a SHA mismatch
  /// discards the partial file so a corrupt resume can't poison the cache.
  /// Returns the final file size; throws the last error when every
  /// mirror is exhausted.
  static Future<int> _fetch(
    List<String> urls,
    File dest,
    String sha,
    int expectedBytes,
    void Function(int downloadedFileBytes) onFileProgress,
  ) async {
    Object? lastError;
    for (final url in urls) {
      for (var attempt = 0; attempt < 3; attempt++) {
        try {
          return await _fetchOnce(
              url, dest, sha, expectedBytes, onFileProgress);
        } catch (e) {
          lastError = e;
          await Future<void>.delayed(Duration(seconds: 1 << attempt));
        }
      }
    }
    throw lastError ?? const HttpException('Model download failed');
  }

  static Future<int> _fetchOnce(
    String url,
    File dest,
    String sha,
    int expectedBytes,
    void Function(int downloadedFileBytes) onFileProgress,
  ) async {
    final tmp = File('${dest.path}.part');
    var resumeFrom = 0;
    if (await tmp.exists()) {
      resumeFrom = await tmp.length();
      if (resumeFrom >= expectedBytes) {
        // Stale/complete partial: re-verify instead of appending forever.
        resumeFrom = 0;
        await tmp.delete();
      }
    }
    final client = HttpClient();
    try {
      final req = await client.getUrl(Uri.parse(url));
      if (resumeFrom > 0) {
        req.headers.set('Range', 'bytes=$resumeFrom-');
      }
      final res = await req.close();
      final resumed = resumeFrom > 0 && res.statusCode == 206;
      if (res.statusCode != 200 && res.statusCode != 206) {
        throw HttpException('Model download failed: HTTP ${res.statusCode}');
      }
      final sink =
          tmp.openWrite(mode: resumed ? FileMode.append : FileMode.write);
      var n = resumed ? resumeFrom : 0;
      onFileProgress(n);
      await for (final chunk in res) {
        sink.add(chunk);
        n += chunk.length;
        onFileProgress(n);
        if (n > expectedBytes) {
          throw const HttpException('Model larger than expected — aborting');
        }
      }
      await sink.flush();
      await sink.close();
      if (n != expectedBytes) {
        // Keep .part for resume on the next attempt.
        throw HttpException('Model truncated ($n vs $expectedBytes bytes)');
      }
      if (await _sha256File(tmp) != sha) {
        try {
          await tmp.delete();
        } catch (_) {}
        throw const FormatException(
            'Model SHA256 mismatch — not official weights');
      }
      await tmp.rename(dest.path);
      return n;
    } finally {
      client.close();
    }
  }
}

/// Thrown when the face-model pack is missing and must be downloaded first.
class ModelPackMissing implements Exception {
  const ModelPackMissing(this.missingBytes);
  final int missingBytes;

  String get message =>
      'Face models not set up yet (~${(missingBytes / 1048576).ceil()} MB one-time setup from the app bundle, no download needed).';
}
