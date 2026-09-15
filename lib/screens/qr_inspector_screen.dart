import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/mosip.dart';

/// Debug: dump a QR's decoded structure (identity keys, sizes, magic)
/// WITHOUT verifying. Use a TEST enrollment — output describes the
/// credential layout but never include faces or secrets.
///
/// Answers "where is the portrait?": look for a bstr with JPEG magic
/// (`ff d8`) — the card reads identity key 63. Anything else (JP2,
/// BDB, another key) shows up here verbatim.
class QrInspectorScreen extends StatefulWidget {
  const QrInspectorScreen({super.key, this.initialText = ''});

  final String initialText;

  @override
  State<QrInspectorScreen> createState() => _QrInspectorScreenState();
}

class _QrInspectorScreenState extends State<QrInspectorScreen> {
  late final _ctrl = TextEditingController(text: widget.initialText);
  String _out = 'Paste a test qrText and tap Inspect.';
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _inspect() async {
    setState(() {
      _busy = true;
      _out = 'Decoding…';
    });
    try {
      final r = await inspectQrTextOffline(_ctrl.text);
      if (!mounted) return;
      final buf = StringBuffer()
        ..writeln('mode: ${r.qrMode}')
        ..writeln('iss: ${r.iss}');
      for (final e in r.entries) {
        buf.writeln('${e.$1}: ${e.$2}');
      }
      setState(() {
        _busy = false;
        _out = buf.toString();
      });
    } on FormatException catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _out = 'Cannot decode: ${e.message}\n'
            '(encrypted QRs need .env ENCRYPTION_KEY to look inside)';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _out = 'Error: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QR inspector (debug)')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Structure only — no signature check, no verdict. '
              'Use a TEST enrollment.',
              style: TextStyle(color: Colors.black54, fontSize: 12),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: _ctrl,
              maxLines: 3,
              decoration: const InputDecoration(
                labelText: 'qrText (Base45)',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 8),
            FilledButton.icon(
              onPressed: _busy ? null : _inspect,
              icon: const Icon(Icons.search),
              label: Text(_busy ? 'Decoding…' : 'Inspect'),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: SingleChildScrollView(
                  child: SelectableText(_out,
                      style: const TextStyle(
                          fontFamily: 'monospace', fontSize: 12)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: _out));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Copied')),
                );
              },
              icon: const Icon(Icons.copy),
              label: const Text('Copy output'),
            ),
          ],
        ),
      ),
    );
  }
}
