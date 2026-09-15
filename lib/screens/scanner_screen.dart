import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../models/card_data.dart';
import '../models/eid_record.dart';
import '../services/eid_parser.dart';
import '../services/mosip.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../widgets/progress_dialog.dart';
import '../widgets/scan_overlay.dart';
import 'face_verify_screen.dart';

enum StatusTone { idle, working, ok, fail }

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(detectionSpeed: DetectionSpeed.normal, facing: CameraFacing.back, torchEnabled: false);
  EidParser? _parser;
  String? _parserError;
  bool _busy = false;
  DateTime? _lastAttempt;

  int _detections = 0;
  String _status = 'QR ကို စောင့်နေသည်…';
  String _detail = 'ကင်မရာကို QR ကုဒ်ဘက်သို့ ချိန်ပါ';
  StatusTone _tone = StatusTone.idle;

  @override
  void initState() {
    super.initState();
    try {
      _parser = EidParser();
    } on FormatException catch (e) {
      _parser = null;
      _parserError = e.message;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Uint8List? extractEnvelopeBytes(Barcode b) {
    final d = b.rawDecodedBytes;
    if (d is DecodedBarcodeBytes) return d.bytes;
    if (d is DecodedVisionBarcodeBytes) return d.bytes ?? d.rawBytes;
    // ignore: deprecated_member_use
    return b.rawBytes;
  }

  static final _b64Pattern = RegExp(r'^[A-Za-z0-9\-_+/=]+$');
  static final _b45Pattern = RegExp(r'^[0-9A-Z $%*+\-./:]+$');
  static bool isMosipQrText(String s) {
    final t = s.trim().toUpperCase();
    return t.length >= 100 && t.length <= 4296 && _b45Pattern.hasMatch(t);
  }

  static bool _looksLikeQrText(String s) => s.length >= 64 && _b64Pattern.hasMatch(s);

  void _setStatus(String status, String detail, [StatusTone tone = StatusTone.idle]) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _detail = detail;
      _tone = tone;
    });
  }

  static String reasonHint(String reason) => switch (reason) {
    'expired' => 'QR expired — re-enroll this person.',
    'not-yet-valid' => 'QR not yet valid — check device clock.',
    'unknown-key' => 'Signed by an unknown issuer — issuer key rotated? Re-pin.',
    'auth-failed' => 'Signature/decrypt failed — tampered QR or wrong key (.env ENCRYPTION_KEY must match the issuer server).',
    'unsupported-legacy-qr' => 'Legacy QR format — re-enroll.',
    _ => 'Not a valid eID QR ($reason).',
  };

  Future<void> _attemptCapture(BarcodeCapture capture) async {
    if (capture.barcodes.isEmpty || !mounted) return;
    _detections++;

    final b = capture.barcodes.first;
    final bytes = extractEnvelopeBytes(b);
    final text = b.rawValue?.trim() ?? '';
    final bytesLen = bytes?.length ?? 0;

    final now = DateTime.now();
    if (_busy || (_lastAttempt != null && now.difference(_lastAttempt!) < const Duration(seconds: 2))) {
      _setStatus('Seen #$_detections (cooling down)…', 'bytes=$bytesLen text=${text.length} format=${b.format.name}');
      return;
    }
    _busy = true;
    _lastAttempt = now;

    try {
      _setStatus('Verifying #$_detections (offline)…', 'bytes=$bytesLen text=${text.length} format=${b.format.name}', StatusTone.working);

      if (isMosipQrText(text)) {
        final qrText = text.toUpperCase();
        try {
          final credential = await showDecryptingDialog(context, verifyQrTextOffline(qrText), label: 'Verifying…');
          if (!mounted) return;
          _setStatus('QR valid ✓ ${credential.name}'.trim(), 'offline ${credential.qrMode} · text=${text.length}', StatusTone.ok);
          await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FaceVerifyScreen(card: CardData.fromMosip(credential, qrText))));
        } on FormatException catch (e) {
          _setStatus('QR invalid ✗ (${e.message})', '${reasonHint(e.message)} text=${text.length}', StatusTone.fail);
        }
        return;
      }

      final record = await showDecryptingDialog(context, _decodeLegacyPaths(bytes, text));
      if (!mounted || record == null) return;
      final legacyQrText = (bytes != null && bytes.isNotEmpty) ? EidParser.envelopeToQrText(bytes) : text;
      _setStatus('Valid ✓ id=${record.id}', 'bytes=$bytesLen text=${text.length}', StatusTone.ok);
      await Navigator.of(context).push(MaterialPageRoute(builder: (_) => FaceVerifyScreen(card: CardData.fromLegacy(record, legacyQrText))));
    } finally {
      _busy = false;
    }
  }

  Future<EidRecord?> _decodeLegacyPaths(Uint8List? bytes, String text) async {
    final parser = _parser;
    if (parser == null) {
      _setStatus('No key', _parserError ?? 'ENCRYPTION_KEY missing.', StatusTone.fail);
      return null;
    }
    String? bytesError;
    if (bytes != null && bytes.isNotEmpty) {
      try {
        return await parser.parseEnvelopeBytes(bytes);
      } on FormatException catch (e) {
        bytesError = e.message;
      }
    }
    if (_looksLikeQrText(text)) {
      try {
        return await parser.parseQrTextB64Url(text);
      } on FormatException catch (e) {
        _setStatus('Unreadable QR ✗ (${e.message})', _hintFor(e.message, bytes?.length ?? 0, text.length, bytesError), StatusTone.fail);
        return null;
      }
    }
    if ((bytes == null || bytes.isEmpty) && text.isEmpty) {
      _setStatus('Empty detection', 'Barcode had neither bytes nor text.', StatusTone.fail);
    } else {
      _setStatus('Unreadable QR ✗ (${bytesError ?? 'malformed-envelope'})', _hintFor(bytesError ?? 'malformed-envelope', bytes?.length ?? 0, text.length, null), StatusTone.fail);
    }
    return null;
  }

  static String _hintFor(String reason, int bytesLen, int textLen, String? bytesError) {
    var extra = 'bytes=$bytesLen text=$textLen.';
    if (bytesLen == 0 && textLen > 0 && textLen < 100) {
      extra += ' Hold steady 15–30 cm, improve focus/light.';
    } else if (bytesError != null && reason != bytesError) {
      extra += ' Byte path said: $bytesError.';
    } else {
      extra += ' Hold steady 15–30 cm in good light.';
    }
    return 'Not a valid eID QR. $extra';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
        title: Text(S.scannerTitle),
        actions: [
          IconButton(tooltip: S.torch, icon: const Icon(Icons.flash_on_outlined), onPressed: () => _controller.toggleTorch()),
          IconButton(tooltip: S.switchCamera, icon: const Icon(Icons.cameraswitch_outlined), onPressed: () => _controller.switchCamera()),
          const SizedBox(width: 15),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 5,
            child: Stack(
              fit: StackFit.expand,
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _attemptCapture,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.no_photography_outlined, size: 48, color: scheme.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            'Camera error: ${error.errorCode}\n'
                            'Grant camera permission and restart.',
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: 0.35), Colors.transparent, Colors.transparent, Colors.black.withValues(alpha: 0.45)], stops: const [0.0, 0.25, 0.7, 1.0]),
                  ),
                ),
                const IgnorePointer(child: ScanOverlay()),
                Positioned(
                  top: 12,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                      decoration: BoxDecoration(color: Colors.black.withValues(alpha: 0.55), borderRadius: BorderRadius.circular(20)),
                      child: Text(S.scannerHint, style: const TextStyle(color: Colors.white, fontSize: 12)),
                    ),
                  ),
                ),
              ],
            ),
          ),
          _StatusSheet(status: _status, detail: _detail, tone: _tone, busy: _busy, detections: _detections),
        ],
      ),
    );
  }
}

class _StatusSheet extends StatelessWidget {
  const _StatusSheet({required this.status, required this.detail, required this.tone, required this.busy, required this.detections});

  final String status;
  final String detail;
  final StatusTone tone;
  final bool busy;
  final int detections;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (tone) {
      StatusTone.ok => (Icons.check_circle, scheme.primary),
      StatusTone.fail => (Icons.error, scheme.error),
      StatusTone.working => (Icons.sync, scheme.tertiary),
      StatusTone.idle => (Icons.cloud_off_outlined, scheme.onSurfaceVariant),
    };
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: scheme.outlineVariant)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (busy && tone == StatusTone.working) SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.5, color: color)) else Icon(icon, size: 22, color: color),
              const SizedBox(width: 10),
              Expanded(
                child: Text(status, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            detail,
            maxLines: 3,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: 8),
          Text(
            'Detections: $detections · ${S.stepScan} → ${S.stepFace} → ${S.stepCard}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant.withValues(alpha: 0.8), fontSize: 11),
          ),
        ],
      ),
    );
  }
}
