import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_avif/flutter_avif.dart';

/// Renders decrypted eID thumb bytes.
///
/// The server issues AVIF thumbs (`fmt == 'avif'`, 128px grayscale) which
/// Flutter's engine cannot decode — those go through `flutter_avif`
/// (bundled libavif, works on every OS version). Anything else (e.g. legacy
/// `jpeg`) uses the framework `Image.memory`.
class IdentityImage extends StatelessWidget {
  const IdentityImage({
    super.key,
    required this.bytes,
    required this.mime,
    required this.label,
  });

  final Uint8List bytes;
  final String mime;
  final String label;

  bool get _isAvif =>
      mime == 'image/avif' || _sniffsAvif(bytes);

  /// Failsafe: trust the bytes, not just `fmt` — AVIF files start with
  /// `....ftypavif`/`ftypavis`/`ftypmif1` in the first 12 bytes.
  static bool _sniffsAvif(Uint8List b) {
    if (b.length < 12) return false;
    if (b[4] != 0x66 || b[5] != 0x74 || b[6] != 0x79 || b[7] != 0x70) {
      return false; // not `ftyp`
    }
    final brand = String.fromCharCodes(b.sublist(8, 12));
    return brand == 'avif' ||
        brand == 'avis' ||
        brand == 'mif1' ||
        brand == 'msf1' ||
        brand == 'miaf';
  }

  @override
  Widget build(BuildContext context) {
    if (_isAvif) {
      return AvifImage.memory(
        bytes,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            _BrokenImage(label: 'Could not render $label ($mime)'),
      );
    }
    return Image.memory(
      bytes,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) =>
          _BrokenImage(label: 'Could not render $label ($mime)'),
    );
  }
}

class _BrokenImage extends StatelessWidget {
  const _BrokenImage({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    return Container(
      height: 180,
      color: Colors.grey.shade200,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(16),
      child: Text(label, textAlign: TextAlign.center),
    );
  }
}
