import 'package:flutter/material.dart';

import 'screens/splash_screen.dart';
import 'ui/app_strings.dart';
import 'ui/app_theme.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const QrIdentityApp());
}

class QrIdentityApp extends StatefulWidget {
  const QrIdentityApp({super.key});

  @override
  State<QrIdentityApp> createState() => _QrIdentityAppState();
}

class _QrIdentityAppState extends State<QrIdentityApp> {
  @override
  void initState() {
    super.initState();
    ThemeController.instance.addListener(_onChanged);
    LanguageController.instance.addListener(_onChanged);
  }

  @override
  void dispose() {
    ThemeController.instance.removeListener(_onChanged);
    LanguageController.instance.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'eID Verify',
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      themeMode: ThemeController.instance.value,
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
