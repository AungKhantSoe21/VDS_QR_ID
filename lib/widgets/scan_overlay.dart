import 'package:flutter/material.dart';

/// Camera viewfinder overlay: rounded corner brackets + a slow shimmer
/// sweep. Pure decoration (IgnorePointer by contract at call site).
class ScanOverlay extends StatefulWidget {
  const ScanOverlay({super.key, this.boxSize = 250});

  final double boxSize;

  @override
  State<ScanOverlay> createState() => _ScanOverlayState();
}

class _ScanOverlayState extends State<ScanOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2200),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Center(
      child: SizedBox(
        width: widget.boxSize,
        height: widget.boxSize,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) => CustomPaint(
            painter: _ViewfinderPainter(
              sweep: _controller.value,
              bracketColor: Colors.white,
            ),
          ),
        ),
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  _ViewfinderPainter({
    required this.sweep,
    required this.bracketColor,
  });

  final double sweep;
  final Color bracketColor;

  @override
  void paint(Canvas canvas, Size size) {
    const bracket = 34.0;
    const width = 5.0;
    const radius = 20.0;
    final paint = Paint()
      ..color = bracketColor.withValues(alpha: 0.95)
      ..strokeWidth = width
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final r = Rect.fromLTWH(0, 0, size.width, size.height);
    for (final corner in [
      (r.topLeft, 0.0),
      (r.topRight, 1.0),
      (r.bottomRight, 2.0),
      (r.bottomLeft, 3.0),
    ]) {
      canvas.save();
      canvas.translate(corner.$1.dx, corner.$1.dy);
      canvas.rotate(corner.$2 * 1.5708);
      final path = Path()
        ..moveTo(0, radius + bracket)
        ..lineTo(0, radius)
        ..arcToPoint(const Offset(radius, 0), radius: const Radius.circular(radius))
        ..lineTo(radius + bracket, 0);
      canvas.drawPath(path, paint);
      canvas.restore();
    }
    // Shimmer sweep — subtle white, not gold.
    final y = size.height * sweep;
    final sweepPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.0),
          Colors.white.withValues(alpha: 0.3),
          Colors.white.withValues(alpha: 0.0),
        ],
        stops: const [0.0, 0.5, 1.0],
      ).createShader(Rect.fromLTWH(0, y - 26, size.width, 52));
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(14, y - 1.5, size.width - 28, 3),
        const Radius.circular(2),
      ),
      sweepPaint,
    );
  }

  @override
  bool shouldRepaint(_ViewfinderPainter old) => old.sweep != sweep;
}

/// Rounded face-frame guide for the selfie hero tile: clean white corners
/// with no gold/yellow. Pure decoration.
class FaceFrameOverlay extends StatelessWidget {
  const FaceFrameOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: AspectRatio(
        aspectRatio: 3 / 4,
        child: FractionallySizedBox(
          widthFactor: 0.72,
          heightFactor: 0.8,
          child: CustomPaint(painter: _FaceFramePainter()),
        ),
      ),
    );
  }
}

class _FaceFramePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final frame = Rect.fromLTWH(0, 0, size.width, size.height);
    // Soft white rounded rectangle outline.
    canvas.drawRRect(
      RRect.fromRectAndRadius(frame, const Radius.circular(36)),
      Paint()
        ..color = Colors.white.withValues(alpha: 0.7)
        ..strokeWidth = 2.5
        ..style = PaintingStyle.stroke,
    );
    // Corner accents — white, not gold.
    const accent = 28.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    for (final (dx, dy, rx, ry) in [
      (0.0, 0.0, 1.0, 1.0),
      (size.width, 0.0, -1.0, 1.0),
      (size.width, size.height, -1.0, -1.0),
      (0.0, size.height, 1.0, -1.0),
    ]) {
      canvas.drawLine(Offset(dx, dy + ry * 36),
          Offset(dx, dy + ry * (36 + accent)), cornerPaint);
      canvas.drawLine(Offset(dx + rx * 36, dy),
          Offset(dx + rx * (36 + accent), dy), cornerPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
