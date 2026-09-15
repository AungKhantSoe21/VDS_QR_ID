import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_identity/services/face_model_pack.dart';

/// Fake model origin: serves fixed bytes with Range support, optional
/// first-hit failure to exercise retry/resume and mirror fallback.
class _Origin {
  _Origin(this.bytes, {this.failFirst = 0});

  final Uint8List bytes;
  int failFirst;
  int hits = 0;
  late HttpServer server;

  static Future<_Origin> bind(Uint8List bytes, {int failFirst = 0}) async {
    final o = _Origin(bytes, failFirst: failFirst);
    o.server = await HttpServer.bind('127.0.0.1', 0);
    o.server.listen(o._handle);
    return o;
  }

  Uri get url =>
      Uri.parse('http://127.0.0.1:${server.port}/model.onnx');

  Future<void> _handle(HttpRequest req) async {
    hits++;
    if (failFirst > 0) {
      failFirst--;
      // Abort mid-stream: client must resume, not restart.
      req.response.statusCode = 200;
      req.response.add(bytes.sublist(0, bytes.length ~/ 3));
      await req.response.close();
      try {
        await req.response.done;
      } catch (_) {}
      return;
    }
    final range = req.headers.value('range');
    var start = 0;
    if (range != null) {
      final m = RegExp(r'bytes=(\d+)-').firstMatch(range);
      if (m != null) start = int.parse(m.group(1)!);
    }
    if (start > 0) {
      if (start >= bytes.length) {
        req.response.statusCode = 416;
        await req.response.close();
        return;
      }
      req.response.statusCode = 206;
      req.response.headers.set(
          'Content-Range', 'bytes $start-${bytes.length - 1}/${bytes.length}');
    }
    req.response.add(bytes.sublist(start));
    await req.response.close();
  }

  Future<void> close() => server.close(force: true);
}

Future<String> _sha(Uint8List b) async {
  final h = await Sha256().hash(b);
  return h.bytes.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
}

void main() {
  test('fetch resumes partial download after mid-stream abort', () async {
    final bytes = Uint8List.fromList(
        List.generate(300000, (i) => (i * 7 + 3) % 256));
    final origin = await _Origin.bind(bytes, failFirst: 1);
    final dir = await Directory.systemTemp.createTemp('pack-resume');
    try {
      final seen = <int>[];
      final n = await FaceModelPack.fetchForTest(
        urls: [origin.url.toString()],
        dest: File('${dir.path}/m.onnx'),
        sha: await _sha(bytes),
        expectedBytes: bytes.length,
        onFileProgress: seen.add,
      );
      expect(n, bytes.length);
      expect(origin.hits, greaterThanOrEqualTo(2));
      // Progress never went backwards overall: final report is complete.
      expect(seen.last, bytes.length);
      expect(File('${dir.path}/m.onnx').readAsBytesSync(), bytes);
    } finally {
      await origin.close();
      await dir.delete(recursive: true);
    }
  });

  test('fetch falls over to mirror when primary fails', () async {
    final bytes =
        Uint8List.fromList(List.generate(50000, (i) => i % 251));
    final bad = await _Origin.bind(bytes);
    final good = await _Origin.bind(bytes);
    final badUrl = bad.url.toString();
    await bad.close(); // connection refused on primary
    final dir = await Directory.systemTemp.createTemp('pack-mirror');
    try {
      final n = await FaceModelPack.fetchForTest(
        urls: [badUrl, good.url.toString()],
        dest: File('${dir.path}/m.onnx'),
        sha: await _sha(bytes),
        expectedBytes: bytes.length,
        onFileProgress: (_) {},
      );
      expect(n, bytes.length);
      expect(good.hits, greaterThanOrEqualTo(1));
      expect(File('${dir.path}/m.onnx').readAsBytesSync(), bytes);
    } finally {
      await good.close();
      await dir.delete(recursive: true);
    }
  });

  test('fetch rejects wrong bytes (SHA mismatch)', () async {
    final bytes = Uint8List.fromList(List.generate(20000, (i) => i % 251));
    final origin = await _Origin.bind(bytes);
    final dir = await Directory.systemTemp.createTemp('pack-sha');
    try {
      await expectLater(
        FaceModelPack.fetchForTest(
          urls: [origin.url.toString()],
          dest: File('${dir.path}/m.onnx'),
          sha: '0' * 64,
          expectedBytes: bytes.length,
          onFileProgress: (_) {},
        ),
        throwsFormatException,
      );
      expect(File('${dir.path}/m.onnx').existsSync(), isFalse);
    } finally {
      await origin.close();
      await dir.delete(recursive: true);
    }
  });
}
