import 'package:flutter/material.dart';

import '../models/card_data.dart';
import '../services/external_finger_reader.dart';
import '../services/face_matcher.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../widgets/verdict_chip.dart';
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
    final canCheckFinger = widget.card.credential != null;
    final scheme = Theme.of(context).colorScheme;
    final match = widget.faceMatch;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
        title: Text(S.cardTitle)),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const VerifyStepsHeader(current: 3),
          const SizedBox(height: 14),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (match != null)
                VerdictChip(
                  icon: match.isMatch
                      ? Icons.face_outlined
                      : Icons.face_retouching_off_outlined,
                  label: match.isMatch ? 'Face match' : 'Face mismatch',
                  color: match.isMatch ? scheme.primary : scheme.error,
                  compact: true,
                )
              else if (widget.visualCheck)
                VerdictChip(
                  icon: Icons.visibility_outlined,
                  label: 'Visual check',
                  color: scheme.tertiary,
                  compact: true,
                ),
              if (_externalFinger != null)
                VerdictChip(
                  icon: Icons.fingerprint,
                  label: _externalFinger!.matched
                      ? 'Finger match'
                      : 'Finger mismatch',
                  color: _externalFinger!.matched
                      ? scheme.primary
                      : scheme.error,
                  compact: true,
                ),
            ],
          ),
          const SizedBox(height: 14),
          SmartCardFlip(
            key: _cardKey,
            card: widget.card,
            faceMatch: widget.faceMatch,
            visualCheck: widget.visualCheck,
            externalFinger: _externalFinger,
          ),
          const SizedBox(height: 10),
          Center(
            child: Text('Tap, swipe, or use Flip',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12)),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: FilledButton.tonalIcon(
                  onPressed: () => _cardKey.currentState?.flip(),
                  icon: const Icon(Icons.flip_camera_android_outlined),
                  label: Text(S.flipCard),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: FilledButton.icon(
                  onPressed: () =>
                      Navigator.of(context).popUntil((r) => r.isFirst),
                  icon: const Icon(Icons.qr_code_scanner_outlined),
                  label: Text(S.scanNext),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (canCheckFinger)
            OutlinedButton.icon(
              onPressed: _openExternalReader,
              icon: const Icon(Icons.fingerprint_outlined),
              label: Text(_externalFinger == null
                  ? S.fingerOptional
                  : '${S.fingerprint} — ${_externalFinger!.matched ? '✓' : '✗'}'),
            ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.primaryContainer,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Text(
              S.verifiedOffline,
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: scheme.onPrimaryContainer, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
