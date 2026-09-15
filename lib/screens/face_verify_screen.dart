import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/card_data.dart';
import '../services/face_matcher.dart';
import '../services/face_model_pack.dart';
import '../widgets/identity_image.dart';
import '../widgets/verify_steps.dart';
import 'smart_card_screen.dart';

/// Step 2 — "same or not": live selfie vs the QR's face data.
///
/// - MOSIP QRs carry a face hash → real on-device auto-match
///   (score vs threshold). A MATCH opens the ID card.
/// - Legacy envelope QRs carry a PHOTO but no hash (and AVIF can't feed
///   the model) → the screen shows QR photo + selfie side by side for
///   an explicit human visual confirm. Labeled as such — never a
///   fabricated score.
class FaceVerifyScreen extends StatefulWidget {
  const FaceVerifyScreen({
    super.key,
    required this.card,
    this.matcher,
  });

  final CardData card;
  final FaceMatcher? matcher;

  @override
  State<FaceVerifyScreen> createState() => _FaceVerifyScreenState();
}

class _FaceVerifyScreenState extends State<FaceVerifyScreen> {
  final _picker = ImagePicker();
  Uint8List? _photo;
  FaceMatchResult? _result;
  String? _error;
  bool _busy = false;

  // One-time model-pack download state (null = not downloading).
  int? _dlDone;
  int? _dlTotal;
  int? _dlNeeded;

  bool get _autoMode => widget.card.faceHash != null;

  Future<void> _capture() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    try {
      final file = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: CameraDevice.front,
        maxWidth: 1024,
        imageQuality: 85,
      );
      if (!mounted) return;
      if (file == null) {
        setState(() => _busy = false);
        return; // user cancelled — stay on screen
      }
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      setState(() {
        _photo = bytes;
        _busy = false;
        _result = null;
      });
      if (_autoMode) await _runMatch(bytes);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Face step failed: $e';
      });
    }
  }

  Future<void> _runMatch(Uint8List bytes) async {
    final credential = widget.card.credential;
    if (credential == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final matcher = widget.matcher ?? FaceMatcher();
      final res = await matcher.matchSelfieVsQr(
        selfieBytes: bytes,
        credential: credential,
      );
      if (!mounted) return;
      setState(() {
        _result = res;
        _busy = false;
      });
    } on ModelPackMissing catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dlNeeded = e.missingBytes;
        _error = 'Face models are not on this device yet.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Face match failed: $e';
      });
    }
  }

  Future<void> _downloadModels() async {
    final photo = _photo;
    if (photo == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _dlDone = 0;
      _dlTotal = FaceModelPack.totalBytes;
    });
    try {
      final pack = await FaceModelPack.system();
      await pack.ensureReady(onProgress: (done, total) {
        if (!mounted) return;
        setState(() {
          _dlDone = done;
          _dlTotal = total;
        });
      });
      if (!mounted) return;
      setState(() {
        _dlDone = null;
        _dlTotal = null;
        _dlNeeded = null;
      });
      await _runMatch(photo);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dlDone = null;
        _error = 'Model download failed: $e';
      });
    }
  }

  void _openCard({FaceMatchResult? match, required bool visual}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => SmartCardScreen(
          card: widget.card,
          faceMatch: match,
          visualCheck: visual,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final res = _result;
    final captured = _photo != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Step 2 · Face check')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const VerifyStepsHeader(current: 2),
          const SizedBox(height: 12),
          Card(
            color: Colors.green.shade50,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.verified,
                      color: Colors.green.shade800, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'QR valid · verifying holder: ${widget.card.name.isEmpty ? '(unnamed)' : widget.card.name}',
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (_autoMode) ...[
            if (_photo != null)
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.memory(_photo!,
                    height: 260, fit: BoxFit.cover),
              )
            else
              Container(
                height: 200,
                decoration: BoxDecoration(
                  color: Colors.grey.shade200,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Center(
                  child: Icon(Icons.face, size: 64, color: Colors.black38),
                ),
              ),
          ] else ...[
            // Visual mode: QR photo vs live selfie, side by side.
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    children: [
                      const Text('QR photo',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: widget.card.portrait == null
                            ? Container(
                                height: 160,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Text('No photo in QR',
                                    style: TextStyle(fontSize: 11)),
                              )
                            : IdentityImage(
                                bytes: widget.card.portrait!,
                                mime: widget.card.portraitMime,
                                label: 'QR photo',
                              ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    children: [
                      const Text('Live selfie',
                          style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: Colors.black54)),
                      const SizedBox(height: 4),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: _photo == null
                            ? Container(
                                height: 160,
                                color: Colors.grey.shade200,
                                alignment: Alignment.center,
                                child: const Icon(Icons.face,
                                    size: 40, color: Colors.black38),
                              )
                            : Image.memory(_photo!,
                                height: 160, fit: BoxFit.cover),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Text(
              'This QR carries a photo but no face hash, so matching is '
              'a human visual check — compare both pictures, then confirm.',
              style: TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ],
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _busy ? null : _capture,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.camera_front),
            label: Text(_busy
                ? 'Working…'
                : _photo == null
                    ? 'Capture live selfie'
                    : 'Retake selfie'),
          ),
          if (_error != null && _dlNeeded == null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (_dlNeeded != null) _DownloadCard(
            neededBytes: _dlNeeded!,
            done: _dlDone,
            total: _dlTotal,
            busy: _busy,
            onDownload: _downloadModels,
          ),
          if (res != null) _ResultCard(result: res),
          const SizedBox(height: 16),
          if (_autoMode) ...[
            if (res?.isMatch == true && captured)
              FilledButton.icon(
                onPressed: () =>
                    _openCard(match: res, visual: false),
                icon: const Icon(Icons.badge),
                label: const Text('Face match — show ID card'),
              )
            else
              const Text(
                'A face MATCH opens the ID card.',
                style: TextStyle(color: Colors.black54),
              ),
          ] else ...[
            if (captured)
              FilledButton.icon(
                onPressed: () => _openCard(visual: true),
                icon: const Icon(Icons.visibility),
                label: const Text('Visually confirmed — show ID card'),
              )
            else
              const Text(
                'Capture a selfie to compare against the QR photo.',
                style: TextStyle(color: Colors.black54),
              ),
          ],
        ],
      ),
    );
  }
}

class _DownloadCard extends StatelessWidget {
  const _DownloadCard({
    required this.neededBytes,
    required this.done,
    required this.total,
    required this.busy,
    required this.onDownload,
  });

  final int neededBytes;
  final int? done;
  final int? total;
  final bool busy;
  final VoidCallback onDownload;

  @override
  Widget build(BuildContext context) {
    final downloading = done != null && total != null;
    final progress =
        downloading && total! > 0 ? (done! / total!).clamp(0.0, 1.0) : 0.0;
    return Card(
      color: Colors.blue.shade50,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Row(
              children: [
                Icon(Icons.download, color: Colors.blue),
                SizedBox(width: 8),
                Expanded(
                  child: Text('One-time face-model download',
                      style: TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              'On-device matching needs the bundled face models '
              '(~${(neededBytes / 1048576).ceil()} MB one-time setup, '
              'copied from the app — no download). '
              'Use Wi-Fi — after this, verification is fully offline.',
              style: const TextStyle(fontSize: 12, color: Colors.black87),
            ),
            const SizedBox(height: 8),
            if (downloading) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 4),
              Text(
                '${(done! / 1048576).toStringAsFixed(1)} / '
                '${(total! / 1048576).toStringAsFixed(1)} MB',
                style: const TextStyle(fontSize: 12),
              ),
            ] else
              FilledButton.icon(
                onPressed: busy ? null : onDownload,
                icon: const Icon(Icons.download),
                label: const Text('Download + verify face'),
              ),
          ],
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result});
  final FaceMatchResult result;

  @override
  Widget build(BuildContext context) {
    final (icon, color, title) = switch (result.status) {
      FaceMatchStatus.match => (
          Icons.check_circle,
          Colors.green,
          'SAME PERSON — face match'
        ),
      FaceMatchStatus.mismatch => (
          Icons.cancel,
          Colors.red,
          'NOT THE SAME — face mismatch'
        ),
      FaceMatchStatus.noFace => (
          Icons.face_retouching_off,
          Colors.orange,
          'NO FACE — retake the selfie'
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w800)),
                ),
              ],
            ),
            if (result.score != null) ...[
              const SizedBox(height: 6),
              Text(
                'Score ${result.score!.toStringAsFixed(3)} vs threshold '
                '${result.threshold?.toStringAsFixed(2) ?? '—'}'
                '${result.backend != null ? ' · ${result.backend}' : ''}',
              ),
            ],
            if (result.detail != null) ...[
              const SizedBox(height: 4),
              Text(result.detail!,
                  style: const TextStyle(
                      fontSize: 12, color: Colors.black54)),
            ],
          ],
        ),
      ),
    );
  }
}
