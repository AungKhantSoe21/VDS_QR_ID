import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/card_data.dart';
import '../services/face_matcher.dart';
import '../services/face_model_pack.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../widgets/identity_image.dart';
import '../widgets/scan_overlay.dart';
import '../widgets/score_gauge.dart';
import '../widgets/verdict_chip.dart';
import '../widgets/verify_steps.dart';
import 'smart_card_screen.dart';

/// Step 2 — "same or not": live selfie vs the QR's face data.
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
        return;
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
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
        title: Text(S.faceTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const VerifyStepsHeader(current: 2),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              VerdictChip(
                icon: Icons.verified,
                label: 'QR မှန်ကန်သည်',
                color: scheme.primary,
                compact: true,
              ),
              VerdictChip(
                icon: Icons.person,
                label: widget.card.name.isEmpty ? '(unnamed)' : widget.card.name,
                color: scheme.tertiary,
                compact: true,
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (_autoMode) ...[
            _SelfieHero(
              photo: _photo,
              busy: _busy,
              onTap: _busy ? null : _capture,
            ),
          ] else ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: _CompareTile(
                    label: S.qrPhoto,
                    child: widget.card.portrait == null
                        ? _PlaceholderBox(
                            height: 170,
                            label: 'No photo in QR',
                          )
                        : IdentityImage(
                            bytes: widget.card.portrait!,
                            mime: widget.card.portraitMime,
                            label: 'QR photo',
                          ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _CompareTile(
                    label: S.liveSelfie,
                    child: _photo == null
                        ? const _PlaceholderBox(
                            height: 170,
                            icon: Icons.face_outlined,
                            label: 'No selfie yet',
                          )
                        : Image.memory(_photo!,
                            height: 170, fit: BoxFit.cover),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(Icons.visibility_outlined,
                        color: scheme.tertiary, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        S.visualHint,
                        style: const TextStyle(
                            fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _busy ? null : _capture,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.camera_front_outlined),
            label: Text(_busy
                ? S.working
                : _photo == null
                    ? S.captureSelfie
                    : S.retakeSelfie),
          ),
          if (_error != null && _dlNeeded == null) ...[
            const SizedBox(height: 10),
            _ErrorCard(message: _error!),
          ],
          if (_dlNeeded != null) ...[
            const SizedBox(height: 10),
            _SetupCard(
              neededBytes: _dlNeeded!,
              done: _dlDone,
              total: _dlTotal,
              busy: _busy,
              onSetup: _downloadModels,
            ),
          ],
          if (res != null) ...[
            const SizedBox(height: 10),
            _ResultCard(result: res),
          ],
          const SizedBox(height: 20),
          if (_autoMode) ...[
            if (res?.isMatch == true && captured)
              FilledButton.icon(
                onPressed: () =>
                    _openCard(match: res, visual: false),
                icon: const Icon(Icons.badge_outlined),
                label: Text(S.showCard),
              )
            else
              Center(
                child: Text(
                  'တူညီမှ ကတ်ပွင့်မည် · A face MATCH opens the ID card.',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ] else ...[
            if (captured)
              FilledButton.icon(
                onPressed: () => _openCard(visual: true),
                icon: const Icon(Icons.visibility_outlined),
                label: Text(S.visualConfirm),
              )
            else
              Center(
                child: Text(
                  'Capture a selfie to compare.',
                  style: TextStyle(
                      color: scheme.onSurfaceVariant, fontSize: 12),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _SelfieHero extends StatelessWidget {
  const _SelfieHero({
    required this.photo,
    required this.busy,
    required this.onTap,
  });

  final Uint8List? photo;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 280,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: scheme.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (photo != null)
              Image.memory(photo!, fit: BoxFit.cover)
            else
              Container(
                color: scheme.surfaceContainerHighest,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.face_outlined,
                        size: 72, color: scheme.onSurfaceVariant),
                    const SizedBox(height: 10),
                    Text(
                      'Center your face',
                      style: TextStyle(
                          fontSize: 13, color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            const IgnorePointer(child: FaceFrameOverlay()),
            if (busy)
              Container(
                color: scheme.scrim.withValues(alpha: 0.35),
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CompareTile extends StatelessWidget {
  const _CompareTile({
    required this.label,
    required this.child,
  });

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          label,
          style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: scheme.onSurface),
        ),
        const SizedBox(height: 6),
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: child,
        ),
      ],
    );
  }
}

class _PlaceholderBox extends StatelessWidget {
  const _PlaceholderBox({
    required this.height,
    this.icon = Icons.image_outlined,
    required this.label,
  });

  final double height;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      height: height,
      color: scheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: scheme.onSurfaceVariant),
          const SizedBox(height: 6),
          Text(label,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  const _ErrorCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      color: scheme.errorContainer,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: scheme.onErrorContainer),
            const SizedBox(width: 10),
            Expanded(
              child: Text(message,
                  style: TextStyle(
                      fontSize: 13, color: scheme.onErrorContainer)),
            ),
          ],
        ),
      ),
    );
  }
}

class _SetupCard extends StatelessWidget {
  const _SetupCard({
    required this.neededBytes,
    required this.done,
    required this.total,
    required this.busy,
    required this.onSetup,
  });

  final int neededBytes;
  final int? done;
  final int? total;
  final bool busy;
  final VoidCallback onSetup;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final settingUp = done != null && total != null;
    final progress = settingUp && total! > 0
        ? (done! / total!).clamp(0.0, 1.0)
        : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(Icons.memory_outlined,
                      color: scheme.onPrimaryContainer),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Face models needed',
                    style: TextStyle(
                        fontSize: 15, fontWeight: FontWeight.w800),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'On-device match (~${(neededBytes / 1048576).ceil()} MB, one-time copy from APK).',
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (settingUp) ...[
              LinearProgressIndicator(value: progress),
              const SizedBox(height: 6),
              Text(
                '${(done! / 1048576).toStringAsFixed(1)} / '
                '${(total! / 1048576).toStringAsFixed(1)} MB',
                style: const TextStyle(fontSize: 12),
              ),
            ] else
              FilledButton.icon(
                onPressed: busy ? null : onSetup,
                icon: const Icon(Icons.download_outlined),
                label: Text(S.setUp),
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
    final scheme = Theme.of(context).colorScheme;
    final (icon, color, title) = switch (result.status) {
      FaceMatchStatus.match => (
          Icons.check_circle,
          scheme.primary,
          S.matchTitle,
        ),
      FaceMatchStatus.mismatch => (
          Icons.cancel,
          scheme.error,
          S.mismatchTitle,
        ),
      FaceMatchStatus.noFace => (
          Icons.face_retouching_off_outlined,
          scheme.tertiary,
          S.noFaceTitle,
        ),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            VerdictChip(
              icon: icon,
              label: title,
              color: color,
            ),
            if (result.score != null) ...[
              const SizedBox(height: 14),
              ScoreGauge(
                score: result.score!,
                threshold: result.threshold ?? 0.0,
                scoreLabel: S.score,
                thresholdLabel: S.threshold,
              ),
            ],
            if (result.backend != null || result.detail != null) ...[
              const SizedBox(height: 8),
              Text(
                [
                  if (result.backend != null) result.backend!,
                  if (result.detail != null) result.detail!,
                ].join(' · '),
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurfaceVariant),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
