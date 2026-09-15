import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/card_data.dart';
import '../models/eid_record.dart';
import '../services/eid_codec.dart';
import '../services/eid_crypto.dart';
import '../services/eid_parser.dart';
import '../services/face_matcher.dart';
import '../services/mosip.dart';
import '../widgets/progress_dialog.dart';
import 'face_verify_screen.dart';
import 'qr_inspector_screen.dart';
import 'settings_screen.dart';

/// Fully-offline flow (no server):
///
/// 1. Scan QR → MOSIP Base45 text (uppercased) → [verifyQrTextOffline]
///    (EdDSA signature + expiry, pinned issuer), or legacy envelope
///    bytes → offline AES-GCM decode → [FaceVerifyScreen]
///    (holder name shown, live selfie, same-or-not).
/// 2. Face match (or visual confirm) → [SmartCardScreen] with holder info.
class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  final MobileScannerController _controller = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
    torchEnabled: false,
  );
  EidParser? _parser;
  String? _parserError;
  bool _busy = false;
  DateTime? _lastAttempt;

  int _detections = 0;
  String _status = 'Waiting for QR…';
  String _detail = 'Point the camera at the code. No network needed.';

  @override
  void initState() {
    super.initState();
    try {
      _parser = EidParser();
    } on FormatException catch (e) {
      _parser = null;
      _parserError = e.message;
    }
    _loadThreshold();
  }

  /// Applies the persisted face-match threshold (set in Settings).
  Future<void> _loadThreshold() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getDouble(SettingsScreen.thresholdKey);
      if (saved != null && saved > 0 && saved < 1) {
        FaceMatcher.hashThreshold = saved;
      }
    } catch (_) {
      // Storage unavailable — keep the default.
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

  /// MOSIP alphanumeric QR (agent.md §4): `0-9A-Z $%*+-./:`, up to 4296
  /// chars. Always uppercased before decode.
  static final _b45Pattern = RegExp(r'^[0-9A-Z $%*+\-./:]+$');
  static bool isMosipQrText(String s) {
    final t = s.trim().toUpperCase();
    return t.length >= 100 && t.length <= 4296 && _b45Pattern.hasMatch(t);
  }

  static bool _looksLikeQrText(String s) =>
      s.length >= 64 && _b64Pattern.hasMatch(s);

  void _setStatus(String status, String detail) {
    if (!mounted) return;
    setState(() {
      _status = status;
      _detail = detail;
    });
  }

  /// Backend `reason` → short human line. Matches agent.md §5 exactly.
  static String reasonHint(String reason) => switch (reason) {
        'expired' => 'QR expired — re-enroll this person.',
        'not-yet-valid' => 'QR not yet valid — check device clock.',
        'unknown-key' =>
          'Signed by an unknown issuer — issuer key rotated? Re-pin.',
        'auth-failed' =>
          'Signature/decrypt failed — tampered QR or wrong key (.env ENCRYPTION_KEY must match the issuer server).',
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
    if (_busy ||
        (_lastAttempt != null &&
            now.difference(_lastAttempt!) < const Duration(seconds: 2))) {
      _setStatus('Seen #$_detections (cooling down)…',
          'bytes=$bytesLen text=${text.length} format=${b.format.name}');
      return;
    }
    _busy = true;
    _lastAttempt = now;

    try {
      _setStatus('Verifying #$_detections (offline)…',
          'bytes=$bytesLen text=${text.length} format=${b.format.name}');

      // Path 1 (current): MOSIP QR → offline verify → face check.
      if (isMosipQrText(text)) {
        final qrText = text.toUpperCase();
        try {
          final credential = await showDecryptingDialog(
              context, verifyQrTextOffline(qrText),
              label: 'Verifying…');
          if (!mounted) return;
          _setStatus('QR valid ✓ ${credential.name}'.trim(),
              'offline ${credential.qrMode} · text=${text.length}');
          await Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => FaceVerifyScreen(
                    card: CardData.fromMosip(credential, qrText))),
          );
        } on FormatException catch (e) {
          _setStatus('QR invalid ✗ (${e.message})',
              '${reasonHint(e.message)} text=${text.length}');
        }
        return;
      }

      // Path 2/3 (legacy envelope): photo + demographics decode offline
      // (image_encryption_backend.md) → same face-check flow, with the
      // QR's real photo bytes on the card.
      final record = await showDecryptingDialog(
          context, _decodeLegacyPaths(bytes, text));
      if (!mounted || record == null) return;
      final legacyQrText = (bytes != null && bytes.isNotEmpty)
          ? EidParser.envelopeToQrText(bytes)
          : text;
      _setStatus('Valid ✓ id=${record.id}',
          'bytes=$bytesLen text=${text.length}');
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => FaceVerifyScreen(
                card: CardData.fromLegacy(record, legacyQrText))),
      );
    } finally {
      _busy = false;
    }
  }

  Future<EidRecord?> _decodeLegacyPaths(
      Uint8List? bytes, String text) async {
    final parser = _parser;
    if (parser == null) {
      _setStatus('No key', _parserError ?? 'ENCRYPTION_KEY missing.');
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
        _setStatus('Unreadable QR ✗ (${e.message})',
            _hintFor(e.message, bytes?.length ?? 0, text.length, bytesError));
        return null;
      }
    }
    if ((bytes == null || bytes.isEmpty) && text.isEmpty) {
      _setStatus('Empty detection', 'Barcode had neither bytes nor text.');
    } else {
      _setStatus('Unreadable QR ✗ (${bytesError ?? 'malformed-envelope'})',
          _hintFor(bytesError ?? 'malformed-envelope', bytes?.length ?? 0,
              text.length, null));
    }
    return null;
  }

  static String _hintFor(
      String reason, int bytesLen, int textLen, String? bytesError) {
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

  /// Offline self-test for the legacy key path (no camera).
  Future<void> _selfTest() async {
    final parser = _parser;
    if (parser == null) {
      _setStatus('Self-test ✗', _parserError ?? 'ENCRYPTION_KEY missing.');
      return;
    }
    try {
      final crypto = EidCrypto();
      const img = <int>[1, 2, 3, 4];
      final payload = EidCodec.encodePayloadV3(
        id: 'self-test',
        ts: 't',
        name: 'Self Test',
        idNumber: 'TEST',
        fmt: 'jpeg',
        passport: Uint8List.fromList(img),
        fingerprint: Uint8List.fromList(img),
      );
      final enc = await crypto.encrypt(payload);
      final envelope = EidCodec.encodeEnvelope(
          version: 3, iv: enc.iv, tag: enc.tag, ct: enc.ct);
      final rec = await parser.parseEnvelopeBytes(envelope);
      if (!mounted) return;
      _setStatus('Self-test ✓ (id=${rec.id})',
          'Legacy key + AES-GCM + CBOR work. MOSIP QRs verify via pinned EdDSA key.');
    } on FormatException catch (e) {
      _setStatus('Self-test ✗ (${e.message})',
          'Key/crypto broken — check .env ENCRYPTION_KEY (64 hex chars).');
    } catch (e) {
      if (mounted) _setStatus('Self-test ✗', 'Unexpected error: $e');
    }
  }

  /// Debug path: paste MOSIP Base45 `qrText` (or legacy base64url).
  /// MOSIP text → offline verify → staged flow.
  Future<void> _pasteQrText() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      _setStatus('Clipboard empty', 'Copy qrText first.');
      return;
    }
    if (_busy) return;
    _busy = true;
    try {
      if (isMosipQrText(text)) {
        _setStatus('Verifying pasted QR (offline)…', 'text=${text.length}');
        try {
          final credential = await showDecryptingDialog(
            context,
            verifyQrTextOffline(text),
            label: 'Verifying…',
          );
          if (!mounted) return;
          _setStatus('QR valid ✓ ${credential.name}'.trim(),
              'offline ${credential.qrMode}');
          await Navigator.of(context).push(
            MaterialPageRoute(
                builder: (_) => FaceVerifyScreen(
                    card: CardData.fromMosip(
                        credential, text.toUpperCase()))),
          );
        } on FormatException catch (e) {
          _setStatus('Pasted QR invalid ✗ (${e.message})',
              reasonHint(e.message));
        }
        return;
      }
      final parser = _parser;
      if (parser == null) {
        _setStatus('No key', _parserError ?? 'ENCRYPTION_KEY missing.');
        return;
      }
      _setStatus('Decoding pasted text…', 'text=${text.length}');
      final record = await showDecryptingDialog(
          context, parser.parseQrTextB64Url(text));
      if (!mounted) return;
      _setStatus('Valid ✓ id=${record.id}', 'from pasted text');
      await Navigator.of(context).push(
        MaterialPageRoute(
            builder: (_) => FaceVerifyScreen(
                card: CardData.fromLegacy(record, text))),
      );
    } on FormatException catch (e) {
      _setStatus('Pasted text unreadable ✗ (${e.message})',
          _hintFor(e.message, 0, text.length, null));
    } catch (e) {
      if (mounted) _setStatus('Error', 'Unexpected error: $e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('eID Verify'),
        actions: [
          IconButton(
            tooltip: 'Toggle torch',
            icon: const Icon(Icons.flash_on),
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            tooltip: 'Switch camera',
            icon: const Icon(Icons.cameraswitch),
            onPressed: () => _controller.switchCamera(),
          ),
          IconButton(
            tooltip: 'Offline self-test (legacy key + crypto, no camera)',
            icon: const Icon(Icons.science),
            onPressed: _selfTest,
          ),
          IconButton(
            tooltip: 'Paste qrText (debug)',
            icon: const Icon(Icons.paste),
            onPressed: _pasteQrText,
          ),
          IconButton(
            tooltip: 'Settings (threshold, models, about)',
            icon: const Icon(Icons.settings),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const SettingsScreen()),
            ),
          ),
          IconButton(
            tooltip: 'QR inspector: dump identity keys/sizes (debug)',
            icon: const Icon(Icons.manage_search),
            onPressed: () async {
              final nav = Navigator.of(context);
              final data =
                  await Clipboard.getData(Clipboard.kTextPlain);
              await nav.push(
                MaterialPageRoute(
                  builder: (_) => QrInspectorScreen(
                      initialText: data?.text?.trim() ?? ''),
                ),
              );
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            flex: 3,
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _attemptCapture,
                  errorBuilder: (context, error) => Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Text(
                        'Camera error: ${error.errorCode}\n'
                        'Grant camera permission and restart.',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),
                IgnorePointer(
                  child: Center(
                    child: Container(
                      width: 240,
                      height: 240,
                      decoration: BoxDecoration(
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.9),
                            width: 3),
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Container(
              width: double.infinity,
              color: Colors.grey.shade100,
              padding: const EdgeInsets.all(12),
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _busy
                            ? const SizedBox(
                                width: 14,
                                height: 14,
                                child: CircularProgressIndicator(
                                    strokeWidth: 2))
                            : const Icon(Icons.cloud_off, size: 16),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(_status,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold)),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                        'Detections: $_detections · scan QR → face → card (fingerprint optional)',
                        style: Theme.of(context).textTheme.bodySmall),
                    Text(_detail,
                        style: Theme.of(context).textTheme.bodySmall),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
