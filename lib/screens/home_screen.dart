import 'package:flutter/material.dart';

import '../ui/app_strings.dart';
import '../ui/app_theme.dart';
import 'scanner_screen.dart';
import 'settings_screen.dart';

/// Root shell after splash: bottom nav between Scanner and Settings.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _ScannerTab(),
          Scaffold(
            appBar: AppBar(
              flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
              title: Text(S.settings),
            ),
            body: const SettingsScreen(),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 20),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(28),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.12),
              blurRadius: 16,
              offset: const Offset(0, 4),       
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: NavigationBar(
            selectedIndex: _tab,
            onDestinationSelected: (i) => setState(() => _tab = i),
            height: 64,
            elevation: 0,
            backgroundColor: Colors.transparent,
            indicatorColor: Theme.of(context).colorScheme.primaryContainer,
            labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
            destinations: [
              NavigationDestination(
                icon: const Icon(Icons.qr_code_scanner_outlined),
                selectedIcon: const Icon(Icons.qr_code_scanner),
                label: S.scannerTitle,
              ),
              NavigationDestination(
                icon: const Icon(Icons.settings_outlined),
                selectedIcon: const Icon(Icons.settings),
                label: S.settings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Scanner landing tab: gradient AppBar + illustration + scan button.
class _ScannerTab extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(56),
        child: AppBar(
          flexibleSpace: Container(decoration: const BoxDecoration(gradient: AppTheme.appBarGradient)),
          title: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Image.asset(
                'assets/card/emblem.png',
                width: 28,
                height: 28,
                errorBuilder: (_, _, _) =>
                    const Icon(Icons.verified_user, size: 24, color: Colors.white),
              ),
              const SizedBox(width: 10),
              Text(
                S.appName,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  fontSize: 18,
                ),
              ),
            ],
          ),
          centerTitle: true,
          backgroundColor: Colors.transparent,
          elevation: 0,
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Illustration: phone scanning a QR card.
              const _ScanIllustration(),
              const SizedBox(height: 32),
              Text(
                S.scannerHint,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const ScannerScreen()),
                  );
                },
                icon: const Icon(Icons.qr_code_scanner_outlined, size: 22),
                label: Text(
                  S.scannerTitle,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Pure-Flutter illustration: a phone outline with a QR card inside and
/// a scan line. No images needed — all CustomPaint.
class _ScanIllustration extends StatelessWidget {
  const _ScanIllustration();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      width: 200,
      height: 260,
      child: CustomPaint(
        painter: _ScanIllustrationPainter(
          phoneColor: scheme.onSurfaceVariant,
          qrColor: scheme.primary,
          scanColor: AppTheme.gold,
        ),
      ),
    );
  }
}

class _ScanIllustrationPainter extends CustomPainter {
  _ScanIllustrationPainter({
    required this.phoneColor,
    required this.qrColor,
    required this.scanColor,
  });

  final Color phoneColor;
  final Color qrColor;
  final Color scanColor;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;

    // --- Phone outline ---
    final phoneR = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.22, 0, w * 0.56, h * 0.72),
      const Radius.circular(18),
    );
    canvas.drawRRect(
      phoneR,
      Paint()
        ..color = phoneColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.5,
    );

    // --- Screen area (slightly inset) ---
    final screenR = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.26, h * 0.06, w * 0.48, h * 0.60),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      screenR,
      Paint()
        ..color = phoneColor.withValues(alpha: 0.08)
        ..style = PaintingStyle.fill,
    );

    // --- QR code block (3x3 grid of squares) ---
    final qrLeft = w * 0.32;
    final qrTop = h * 0.16;
    final qrSize = w * 0.36;
    final cell = qrSize / 5;
    final qrPaint = Paint()..color = qrColor;
    // Draw a simple QR-like pattern.
    const pattern = [
      [1, 1, 1, 0, 1],
      [1, 0, 1, 1, 0],
      [1, 1, 0, 1, 1],
      [0, 1, 1, 0, 1],
      [1, 0, 1, 1, 1],
    ];
    for (var r = 0; r < 5; r++) {
      for (var c = 0; c < 5; c++) {
        if (pattern[r][c] == 1) {
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(qrLeft + c * cell, qrTop + r * cell, cell - 1, cell - 1),
              const Radius.circular(2),
            ),
            qrPaint,
          );
        }
      }
    }

    // --- Scan line (horizontal gold bar) ---
    final scanY = h * 0.36;
    final scanPaint = Paint()
      ..shader = LinearGradient(
        colors: [
          scanColor.withValues(alpha: 0.0),
          scanColor.withValues(alpha: 0.8),
          scanColor.withValues(alpha: 0.0),
        ],
      ).createShader(Rect.fromLTWH(w * 0.24, scanY - 1.5, w * 0.52, 3));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.24, scanY - 1.5, w * 0.52, 3),
        const Radius.circular(2),
      ),
      scanPaint,
    );

    // --- Card below the phone (the QR card being scanned) ---
    final cardTop = h * 0.76;
    final cardR = RRect.fromRectAndRadius(
      Rect.fromLTWH(w * 0.10, cardTop, w * 0.80, h * 0.20),
      const Radius.circular(10),
    );
    canvas.drawRRect(
      cardR,
      Paint()
        ..color = phoneColor.withValues(alpha: 0.15)
        ..style = PaintingStyle.fill,
    );
    canvas.drawRRect(
      cardR,
      Paint()
        ..color = phoneColor.withValues(alpha: 0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    // Mini QR on the card.
    final miniQrSize = h * 0.10;
    final miniQrLeft = w * 0.18;
    final miniQrTop = cardTop + (h * 0.20 - miniQrSize) / 2;
    final miniCell = miniQrSize / 3;
    final miniPaint = Paint()..color = qrColor.withValues(alpha: 0.5);
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        if ((r + c) % 2 == 0) {
          canvas.drawRect(
            Rect.fromLTWH(miniQrLeft + c * miniCell, miniQrTop + r * miniCell, miniCell - 1, miniCell - 1),
            miniPaint,
          );
        }
      }
    }
    // Lines on the card (text placeholder).
    final linePaint = Paint()..color = phoneColor.withValues(alpha: 0.2);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, cardTop + h * 0.04, w * 0.40, h * 0.02),
        const Radius.circular(2),
      ),
      linePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, cardTop + h * 0.08, w * 0.30, h * 0.02),
        const Radius.circular(2),
      ),
      linePaint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(w * 0.40, cardTop + h * 0.12, w * 0.35, h * 0.02),
        const Radius.circular(2),
      ),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
