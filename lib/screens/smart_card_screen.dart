import 'package:flutter/material.dart';

import '../models/card_data.dart';
import '../services/external_finger_reader.dart';
import '../services/face_matcher.dart';
import '../widgets/smart_card.dart';
import '../widgets/verify_steps.dart';
import 'external_reader_screen.dart';

/// Final screen — the holder smart card. Shown after QR verified
/// offline (step 1) + face step (step 2: auto match or visual confirm).
/// Fingerprint via external reader is OPTIONAL (button below).
class SmartCardScreen extends StatefulWidget {
  const SmartCardScreen({
    super.key,
    required this.card,
    required this.faceMatch,
    this.visualCheck = false,
  });

  final CardData card;
  final FaceMatchResult? faceMatch;
  final bool visualCheck;

  @override
  State<SmartCardScreen> createState() => _SmartCardScreenState();
}

class _SmartCardScreenState extends State<SmartCardScreen> {
  final _cardKey = GlobalKey<SmartCardFlipState>();
  FingerMatch? _externalFinger;

  Future<void> _openExternalReader() async {
    final fmr = widget.card.credential?.fmr;
    final res = await Navigator.of(context).push<FingerMatch?>(
      MaterialPageRoute(
        builder: (_) => ExternalReaderScreen(fmrRef: fmr),
      ),
    );
    if (!mounted) return;
    if (res != null) {
      setState(() => _externalFinger = res);
    }
  }

  @override
  Widget build(BuildContext context) {
    // External 1:1 needs an FMR reference — only MOSIP QRs carry one.
    final canCheckFinger = widget.card.credential != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Identity card')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const VerifyStepsHeader(current: 3),
          const SizedBox(height: 12),
          SmartCardFlip(
            key: _cardKey,
            card: widget.card,
            faceMatch: widget.faceMatch,
            visualCheck: widget.visualCheck,
            externalFinger: _externalFinger,
          ),
          const SizedBox(height: 8),
          const Center(
            child: Text('Tap, swipe, or use Flip to turn it over',
                style: TextStyle(color: Colors.black54, fontSize: 12)),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _cardKey.currentState?.flip(),
                  icon: const Icon(Icons.flip_camera_android),
                  label: const Text('Flip card'),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: const Icon(Icons.qr_code_scanner),
                  label: const Text('Scan next'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          if (canCheckFinger)
            OutlinedButton.icon(
              onPressed: _openExternalReader,
              icon: const Icon(Icons.fingerprint),
              label: Text(_externalFinger == null
                  ? 'Fingerprint (external reader, optional)'
                  : 'Fingerprint: ${_externalFinger!.matched ? 'MATCH ✓' : 'MISMATCH ✗'} — recheck'),
            ),
          const SizedBox(height: 8),
          const Center(
            child: Text(
              'Verified fully offline. No network was used.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.black54, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
