import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/external_finger_reader.dart';

/// OPTIONAL fingerprint step via an EXTERNAL reader (OTG scanner).
///
/// Reached from the smart card — never a gate. [fmrRef] is the QR's
/// FMR reference (MOSIP QRs only — legacy QRs carry a fingerprint
/// photo, not matchable minutiae, so the button stays hidden there).
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
    return Scaffold(
      appBar: AppBar(title: const Text('Fingerprint (external, optional)')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('QR FINGERPRINT REFERENCE',
                      style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1.4,
                          color: Colors.black54)),
                  const SizedBox(height: 6),
                  Text(
                    ref == null
                        ? 'This QR carries a fingerprint photo, not FMR '
                            'minutiae — external 1:1 matching needs an FMR '
                            'reference (MOSIP QRs).'
                        : 'ISO 19794-2 FMR — ${ref.length} bytes in QR. '
                            'Capture with the external reader for a 1:1 match.',
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'The phone sensor is not used: it cannot match a live '
                    'finger against the QR minutiae.',
                    style: TextStyle(fontSize: 12, color: Colors.black54),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed:
                (_busy || widget.fmrRef == null) ? null : _verify,
            icon: _busy
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.fingerprint),
            label: Text(_busy ? 'Waiting for reader…' : 'Capture + match'),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: const TextStyle(color: Colors.red)),
          ],
          if (m != null) ...[
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Row(
                  children: [
                    Icon(m.matched ? Icons.check_circle : Icons.cancel,
                        color: m.matched ? Colors.green : Colors.red),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        m.matched
                            ? 'FINGERPRINT MATCH — score ${m.score.toStringAsFixed(3)} vs ${m.threshold.toStringAsFixed(2)}'
                            : 'FINGERPRINT MISMATCH — score ${m.score.toStringAsFixed(3)} vs ${m.threshold.toStringAsFixed(2)}',
                        style:
                            const TextStyle(fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
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
