// Debug decoder for real enroll vectors (guide §7).
//
// Usage:
// ```sh
// dart run tool/decode_qr_b64url.dart --qrText '<qrEnvelopeB64url>' [--key <hex>] [--out /tmp/eid]
// ```
// Decrypts offline and writes `passport.bin` + `fingerprint.bin`,
// printing id/ts/name/idNumber/fmt. Key precedence: --key,
// then the project `.env` (ENCRYPTION_KEY).
import 'dart:io';

import 'package:qr_identity/config/eid_key.dart';
import 'package:qr_identity/config/env_parse.dart';
import 'package:qr_identity/services/eid_crypto.dart';
import 'package:qr_identity/services/eid_parser.dart';

Future<void> main(List<String> args) async {
  String? qrText;
  String? keyHex;
  String? outDir;

  for (var i = 0; i < args.length; i++) {
    switch (args[i]) {
      case '--qrText':
        qrText = args[++i];
      case '--key':
        keyHex = args[++i];
      case '--out':
        outDir = args[++i];
      case '--help' || '-h':
        stdout.writeln('See file header for usage.');
        return;
    }
  }

  if (qrText == null || qrText.isEmpty) {
    stderr.writeln('Required: --qrText \'<qrEnvelopeB64url>\'');
    exit(2);
  }

  // Plain `dart run` has no Flutter asset bundle, so read the project
  // `.env` directly as a fallback (the app loads the same file as an asset).
  final envKey =
      keyHex?.isNotEmpty == true ? null : _readEnvKey();
  final key = eidKeyBytes(
      overrideHex: keyHex?.isNotEmpty == true ? keyHex : envKey);
  final rec = await EidParser(crypto: EidCrypto(keyBytes: key))
      .parseQrTextB64Url(qrText);

  stdout.writeln('version:   ${rec.version}');
  stdout.writeln('id:        ${rec.id}');
  stdout.writeln('ts:        ${rec.timestamp}');
  stdout.writeln('name:      ${rec.name}');
  stdout.writeln('idNumber:  ${rec.idNumber}');
  stdout.writeln('fmt:       ${rec.format} (${rec.mime})');
  stdout.writeln('passport:  ${rec.passport.length} bytes');
  stdout.writeln('fingerprint: ${rec.fingerprint.length} bytes');

  if (outDir != null) {
    await Directory(outDir).create(recursive: true);
    await File('$outDir/passport.bin').writeAsBytes(rec.passport);
    await File('$outDir/fingerprint.bin').writeAsBytes(rec.fingerprint);
    stdout.writeln('Wrote $outDir/passport.bin + fingerprint.bin');
  }
}

/// Project `.env` reader (shared parser, no Flutter needed).
String? _readEnvKey() {
  final candidates = <File>[
    File('.env'), // `dart run` from the project root
    File('${File(Platform.script.toFilePath()).parent.parent.path}'
        '${Platform.pathSeparator}.env'), // relative to tool/
  ];
  for (final f in candidates) {
    try {
      if (!f.existsSync()) continue;
      final v = parseEnv(f.readAsStringSync())['ENCRYPTION_KEY']?.trim();
      if (v?.isNotEmpty == true) return v;
    } catch (_) {
      continue;
    }
  }
  return null;
}
