import 'package:flutter/material.dart';

import '../services/face_model_pack.dart';
import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import '../widgets/section_header.dart';

/// Settings: appearance (theme + language), on-device model pack, about.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  bool _modelsReady = false;
  int _modelsMissing = 0;
  int? _dlDone;
  int? _dlTotal;
  bool _busy = false;
  String? _notice;

  @override
  void initState() {
    super.initState();
    _refreshModels();
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
        _notice = 'Setup failed: $e';
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
      if (!mounted) return;
      setState(() {
        _busy = false;
        _notice = 'Model cache cleared (~31MB).';
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
    return ListenableBuilder(
      listenable: LanguageController.instance,
      builder: (context, _) {
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
              // Language
              SectionHeader(S.languageSection),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: SegmentedButton<String>(
                    segments: [
                      ButtonSegment(
                        value: 'my',
                        label: Text(S.langMy,
                            style: const TextStyle(fontSize: 13)),
                      ),
                      ButtonSegment(
                        value: 'en',
                        label: Text(S.langEn,
                            style: const TextStyle(fontSize: 13)),
                      ),
                    ],
                    selected: {LanguageController.instance.value},
                    onSelectionChanged: (s) =>
                        LanguageController.instance.setLang(s.first),
                    showSelectedIcon: false,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Appearance
              SectionHeader(S.appearanceSection),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: ValueListenableBuilder<ThemeMode>(
                    valueListenable: ThemeController.instance,
                    builder: (_, mode, _) => SegmentedButton<ThemeMode>(
                      segments: [
                        ButtonSegment(
                          value: ThemeMode.system,
                          icon: const Icon(Icons.settings_suggest_outlined,
                              size: 18),
                          label: Text(S.themeSystem,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: ThemeMode.light,
                          icon: const Icon(Icons.light_mode_outlined,
                              size: 18),
                          label: Text(S.themeLight,
                              style: const TextStyle(fontSize: 12)),
                        ),
                        ButtonSegment(
                          value: ThemeMode.dark,
                          icon: const Icon(Icons.dark_mode_outlined,
                              size: 18),
                          label: Text(S.themeDark,
                              style: const TextStyle(fontSize: 12)),
                        ),
                      ],
                      selected: {mode},
                      onSelectionChanged: (s) =>
                          ThemeController.instance.setMode(s.first),
                      showSelectedIcon: false,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              // Models
              SectionHeader(S.modelsSection),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(
                              _modelsReady
                                  ? Icons.check_circle
                                  : Icons.memory_outlined,
                              color: _modelsReady
                                  ? Theme.of(context).colorScheme.primary
                                  : Theme.of(context)
                                      .colorScheme
                                      .onSurfaceVariant),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Text(
                              _modelsReady
                                  ? 'Ready (~31MB, SHA-verified)'
                                  : 'Not set up (~${(_modelsMissing / 1048576).ceil()} MB, offline)',
                              style: const TextStyle(
                                  fontWeight: FontWeight.w600, fontSize: 13),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (downloading) ...[
                        LinearProgressIndicator(value: progress),
                        const SizedBox(height: 6),
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
                                icon: const Icon(Icons.download_outlined),
                                label: Text(S.setUp),
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: OutlinedButton.icon(
                                onPressed: _busy || !_modelsReady
                                    ? null
                                    : _clearModels,
                                icon: const Icon(Icons.delete_outline),
                                label: Text(S.clearCache),
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
              if (_notice != null) ...[
                const SizedBox(height: 10),
                Text(_notice!,
                    style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurface)),
              ],
              const SizedBox(height: 20),
              SectionHeader(S.aboutSection),
              const SizedBox(height: 8),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Text(
                    'eID Verify 0.9.0 (PoC)\n\n'
                    'Offline identity check: QR authenticity (EdDSA + expiry) → '
                    'on-device face match (EdgeFace-S + legacy buffalo) → ID card. '
                    'Fingerprint via external reader is optional.\n\n'
                    'Formats: MOSIP Claim 169 Base45 QR + legacy envelope v2/v3. '
                    'Conceptually aligned with ICAO VDS (offline signed '
                    'credential); not VDS-conformant (no X.509/CSCA chain).',
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ),
            ],
        );
      },
    );
  }
}
