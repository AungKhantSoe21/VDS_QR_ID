import 'dart:typed_data';

/// Server `ENCRYPTION_KEY` (64 hex chars = 32 bytes, AES-256).
///
/// No `--dart-define` needed. The key comes from the project `.env` file
/// (`ENCRYPTION_KEY=...`), loaded at startup by `main()` into
/// [EidKeyConfig] and gitignored. Tests / debug tools pass [overrideHex].
///
/// Source of truth for the value: the server `.env` (`ENCRYPTION_KEY`),
/// see `MOBILE_SCANNER.md §1.1`.
///
/// Startup-provided key material (sync-readable anywhere).
class EidKeyConfig {
  static String? _envFileHex;

  /// Called once from `main()` after reading the `.env` asset.
  static void setEnvFileHex(String? hex) => _envFileHex = hex;

  /// Visible for tests.
  static void resetForTest() => _envFileHex = null;
}

/// Parses the EID key from the `.env` asset ([EidKeyConfig]) unless
/// [overrideHex] is given (tests / debug tools).
Uint8List eidKeyBytes({String? overrideHex}) {
  final hex = (overrideHex ?? EidKeyConfig._envFileHex ?? '')
      .trim()
      .toLowerCase();
  if (hex.isEmpty) {
    throw const FormatException(
      'ENCRYPTION_KEY missing. Add ENCRYPTION_KEY=<64 hex chars> to the '
      'project .env file (see MOBILE_SCANNER.md §1.1).',
    );
  }
  if (hex.length != 64 || !_isHex(hex)) {
    throw const FormatException(
        'ENCRYPTION_KEY must be exactly 64 hex chars (32 bytes).');
  }
  return hexDecode(hex);
}

Uint8List hexDecode(String hex) {
  final out = Uint8List(hex.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(hex.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

bool _isHex(String s) {
  for (var i = 0; i < s.length; i++) {
    final c = s.codeUnitAt(i);
    final ok = (c >= 48 && c <= 57) || (c >= 97 && c <= 102);
    if (!ok) return false;
  }
  return true;
}
