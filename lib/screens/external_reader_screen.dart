import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/external_finger_reader.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../widgets/score_gauge.dart';
import '../widgets/section_header.dart';
import '../widgets/verdict_chip.dart';

/// OPTIONAL fingerprint step via an EXTERNAL reader (OTG scanner).
class ExternalReaderScreen extends StatefulWidget {
  const ExternalReaderScreen({
    super.key,
    required this.fmrRef,
    this.reader = const UnimplementedReader(),
  });

  final Uint8List? fmrRef;
  final ExternalFingerprintReader reader;

  @override
  State<ExternalReaderScreen> createState() => _ExternalReaderScreenState();
}

class _ExternalReaderScreenState extends State<ExternalReaderScreen> {
  FingerMatch? _match;
  String? _error;
  bool _busy = false;

  Future<void> _verify() async {
    final ref = widget.fmrRef;
    if (ref == null) return;
    setState(() {
      _busy = true;
      _error = null;
      _match = null;
    });
    try {
      final sample = await widget.reader.capture();
      final m = await widget.reader.match(sample, ref);
      if (!mounted) return;
      setState(() {
        _busy = false;
        _match = m;
      });
    } on ReaderNotConnected catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = e.detail;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = 'Fingerprint failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final m = _match;
    final ref = widget.fmrRef;
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
        title: Text('${S.fingerprint} (optional)')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SectionHeader('QR fingerprint reference'),
                  const SizedBox(height: 8),
                  Text(
                    ref == null
                        ? 'This QR carries a fingerprint photo, not FMR '
                            'minutiae — external 1:1 matching needs an FMR '
                            'reference (MOSIP QRs).'
                        : 'ISO 19794-2 FMR — ${ref.length} bytes in QR. '
                            'Capture with the external reader for a 1:1 match.',
                    style: const TextStyle(fontSize: 13),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'The phone sensor is not used: it cannot match a live '
                    'finger against the QR minutiae.',
                    style: TextStyle(
                        fontSize: 12, color: scheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 14),
          FilledButton.icon(
            onPressed:
                (_busy || widget.fmrRef == null) ? null : _verify,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2.5))
                : const Icon(Icons.fingerprint_outlined),
            label: Text(_busy
                ? 'Waiting for reader…'
                : 'Capture + match'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 10),
            Card(
              color: scheme.errorContainer,
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Text(_error!,
                    style: TextStyle(
                        fontSize: 13, color: scheme.onErrorContainer)),
              ),
            ),
          ],
          if (m != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VerdictChip(
                      icon: m.matched
                          ? Icons.check_circle
                          : Icons.cancel,
                      label: m.matched
                          ? 'FINGERPRINT MATCH'
                          : 'FINGERPRINT MISMATCH',
                      color: m.matched ? scheme.primary : scheme.error,
                    ),
                    const SizedBox(height: 14),
                    ScoreGauge(
                      score: m.score,
                      threshold: m.threshold,
                      scoreLabel: S.score,
                      thresholdLabel: S.threshold,
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.tonalIcon(
              onPressed: () => Navigator.of(context).pop(m),
              icon: const Icon(Icons.check),
              label: const Text('Show on card'),
            ),
          ],
        ],
      ),
    );
  }
}
