import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'config/eid_key.dart';
import 'config/env_parse.dart';
import 'screens/scanner_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Load the gitignored project .env (ENCRYPTION_KEY = CEK for encrypted
  // QRs). Missing/unreadable is tolerated — the scanner shows the config
  // error at scan time. Fully offline: no server, no dart-define.
  try {
    final raw = await rootBundle.loadString('.env');
    EidKeyConfig.setEnvFileHex(parseEnv(raw)['ENCRYPTION_KEY']);
  } catch (_) {
    // No .env asset — key resolution reports the problem at scan time.
  }
  runApp(const QrIdentityApp());
}

class QrIdentityApp extends StatelessWidget {
  const QrIdentityApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eID Verify',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
            seedColor: const Color(0xFF1B5E20)),
        useMaterial3: true,
      ),
      home: const ScannerScreen(),
    );
  }
}
