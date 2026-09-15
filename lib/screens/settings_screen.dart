import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../services/face_matcher.dart';
import '../services/face_model_pack.dart';

/// PoC settings: face-match threshold, on-device model pack, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  /// SharedPreferences key for the persisted face-match threshold.
  static const thresholdKey = 'face_hash_threshold';

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _thresholdCtrl = TextEditingController();
  bool _modelsReady = false;
  int _modelsMissing = 0;
  int? _dlDone;
  int? _dlTotal;
  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _thresholdCtrl.text = FaceMatcher.hashThreshold.toStringAsFixed(2);
    _refreshModels();
  }

  @override
  void dispose() {
    _thresholdCtrl.dispose();
    super.dispose();
  }

  Future<void> _refreshModels() async {
    try {
      final pack = await FaceModelPack.system();
      final ready = await pack.isReady();
      final missing = await pack.missingBytes();
      if (!mounted) return;
      setState(() {
        _modelsReady = ready;
        _modelsMissing = missing;
      });
    } catch (_) {}
  }

  Future<void> _saveThreshold() async {
    final parsed = double.tryParse(_thresholdCtrl.text.trim());
    if (parsed == null || parsed <= 0 || parsed >= 1) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Threshold must be between 0 and 1')),
      );
      _thresholdCtrl.text = FaceMatcher.hashThreshold.toStringAsFixed(2);
      return;
    }
    final clamped = parsed.clamp(0.30, 0.95);
    FaceMatcher.hashThreshold = clamped;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setDouble(SettingsScreen.thresholdKey, clamped);
    } catch (_) {}
    if (!mounted) return;
    _thresholdCtrl.text = clamped.toStringAsFixed(2);
    setState(() {
      _notice = 'Face threshold set to ${clamped.toStringAsFixed(2)} '
          '(higher = stricter).';
    });
  }

  Future<void> _downloadModels() async {
    setState(() {
      _busy = true;
      _notice = null;
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
        _busy = false;
        _dlDone = null;
        _dlTotal = null;
        _notice = 'Model pack ready — face verification works offline.';
      });
      await _refreshModels();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _dlDone = null;
        _notice = 'Download failed: $e';
      });
    }
  }

  Future<void> _clearModels() async {
    setState(() {
      _busy = true;
      _notice = null;
    });
    try {
      final pack = await FaceModelPack.system();
      await pack.clear();
      FaceMatcher.resetEngineForTest();
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Model cache cleared (~31MB freed).';
      });
      await _refreshModels();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Clear failed: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final downloading = _dlDone != null && _dlTotal != null;
    final progress = downloading && _dlTotal! > 0
        ? (_dlDone! / _dlTotal!).clamp(0.0, 1.0)
        : 0.0;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text('FACE MATCH',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _thresholdCtrl,
                  decoration: const InputDecoration(
                    labelText: 'Threshold (0–1)',
                    helperText:
                        'Minimum score for SAME. Raise if strangers pass.',
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: const TextInputType.numberWithOptions(
                      decimal: true),
                  onSubmitted: (_) => _saveThreshold(),
                ),
              ),
              const SizedBox(width: 8),
              FilledButton.tonal(
                onPressed: _saveThreshold,
                child: const Text('Set'),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Text('FACE MODELS (ON-DEVICE)',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                          _modelsReady
                              ? Icons.check_circle
                              : Icons.download,
                          color: _modelsReady
                              ? Colors.green
                              : Colors.black54),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _modelsReady
                              ? 'Ready (~31MB bundled models, SHA-verified)'
                              : 'Not set up (~${(_modelsMissing / 1048576).ceil()} MB one-time setup, offline)',
                          style: const TextStyle(
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  if (downloading) ...[
                    LinearProgressIndicator(value: progress),
                    const SizedBox(height: 4),
                    Text(
                      '${(_dlDone! / 1048576).toStringAsFixed(1)} / '
                      '${(_dlTotal! / 1048576).toStringAsFixed(1)} MB',
                      style: const TextStyle(fontSize: 12),
                    ),
                  ] else
                    Row(
                      children: [
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _busy || _modelsReady
                                ? null
                                : _downloadModels,
                            icon: const Icon(Icons.download),
                            label: const Text('Set up'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _busy || !_modelsReady
                                ? null
                                : _clearModels,
                            icon: const Icon(Icons.delete_outline),
                            label: const Text('Clear cache'),
                          ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
          ),
          if (_notice != null) ...[
            const SizedBox(height: 8),
            Text(_notice!,
                style: const TextStyle(
                    fontSize: 12, color: Colors.black87)),
          ],
          const SizedBox(height: 16),
          const Text('ABOUT',
              style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                  color: Colors.black54)),
          const SizedBox(height: 8),
          const Card(
            child: Padding(
              padding: EdgeInsets.all(14),
              child: Text(
                'eID Verify 0.9.0 (PoC)\n\n'
                'Offline identity check: QR authenticity (EdDSA + expiry) → '
                'on-device face match (EdgeFace-S) → ID card. '
                'Fingerprint via external reader is optional.\n\n'
                'Formats: MOSIP Claim 169 Base45 QR + legacy envelope v2/v3. '
                'Conceptually aligned with ICAO VDS (offline signed '
                'credential); not VDS-conformant (no X.509/CSCA chain).',
                style: TextStyle(fontSize: 12, color: Colors.black87),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
