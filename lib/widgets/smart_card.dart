import 'dart:math';

import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../models/card_data.dart';
import '../services/external_finger_reader.dart';
import '../services/face_matcher.dart';

/// Smart-card presentation of a verified [CardData] (either QR format).
///
/// Front follows `id_layout_card.md` / `docs/VDS Card Back.png` (Myanmar
/// NRC style): VDS header, name / UID / national-reg + QR, and a
/// DOB–gender–expiry footer; decorative border strip at the bottom;
/// pale-green temple guilloche theme.
///
/// Info only, no portrait: the QR's face data is a verification
/// *pattern*, not a display photo.
///
/// Tap or swipe (or [SmartCardFlipState.flip]) to turn it over.
class SmartCardFlip extends StatefulWidget {
  const SmartCardFlip({
    super.key,
    required this.card,
    required this.faceMatch,
    this.visualCheck = false,
    required this.externalFinger,
  });

  final CardData card;
  final FaceMatchResult? faceMatch;

  /// True when a human verifier confirmed QR photo vs holder
  /// (legacy QRs carry a photo but no face hash to auto-match).
  final bool visualCheck;

  /// Null = external fingerprint check skipped (it is optional).
  final FingerMatch? externalFinger;

  @override
  SmartCardFlipState createState() => SmartCardFlipState();
}

class SmartCardFlipState extends State<SmartCardFlip>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  );
  bool _front = true;

  bool get isFront => _front;

  double get _t => Curves.easeInOutCubic.transform(_controller.value);

  double get _lift => sin(_t * pi);

  void flip() {
    if (_front) {
      _goBack();
    } else {
      _goFront();
    }
  }

  void _goFront() {
    setState(() => _front = true);
    _controller.animateTo(0, duration: const Duration(milliseconds: 600));
  }

  void _goBack() {
    setState(() => _front = false);
    _controller.animateTo(1, duration: const Duration(milliseconds: 600));
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final width = context.size?.width ?? 300;
    if (width <= 0) return;
    _controller.value = (_controller.value - details.delta.dx / width).clamp(
      0.0,
      1.0,
    );
  }

  void _onDragEnd(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity < -400) {
      _goBack();
    } else if (velocity > 400) {
      _goFront();
    } else if (_controller.value > 0.5) {
      _goBack();
    } else {
      _goFront();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: flip,
      onHorizontalDragUpdate: _onDragUpdate,
      onHorizontalDragEnd: _onDragEnd,
      child: AspectRatio(
        aspectRatio: 1.586,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (_, _) {
            final angle = _t * pi;
            final lift = _lift;
            final scale = 1.0 - 0.06 * lift;
            return Transform(
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.0012)
                ..rotateY(angle),
              alignment: Alignment.center,
              child: Transform.scale(
                scale: scale,
                child: _t < 0.5
                    ? _CardFront(card: widget.card, lift: lift)
                    : Transform(
                        transform: Matrix4.identity()..rotateY(pi),
                        alignment: Alignment.center,
                        child: _CardBack(
                          card: widget.card,
                          faceMatch: widget.faceMatch,
                          visualCheck: widget.visualCheck,
                          externalFinger: widget.externalFinger,
                          lift: lift,
                        ),
                      ),
              ),
            );
          },
        ),
      ),
    );
  }
}

const _radius = BorderRadius.all(Radius.circular(12));
const _deepGreen = Color(0xFF1B5E20);
const _ink = Color(0xFF102027);

const _months = [
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];

/// `YYYYMMDD` → `11 Nov 1995` ('' → '—').
String fmtDateLong(String yyyymmdd) {
  if (yyyymmdd.length != 8) return yyyymmdd.isEmpty ? '—' : yyyymmdd;
  final y = int.tryParse(yyyymmdd.substring(0, 4));
  final m = int.tryParse(yyyymmdd.substring(4, 6));
  final d = int.tryParse(yyyymmdd.substring(6, 8));
  if (y == null || m == null || d == null || m < 1 || m > 12) {
    return yyyymmdd;
  }
  return '$d ${_months[m - 1]} $y';
}

String fmtEpochLong(int epochSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  return '${d.day} ${_months[d.month - 1]} ${d.year}';
}

// ------------------------------------------------------------ VDS artwork
//
// Real artwork cropped from `docs/VDS Card Back.png` lives under
// `assets/card/` (emblem, flag, border strip). Each loader falls back
// to the painted stand-in when the asset is missing, so the card
// never breaks (tests, missing bundle, future re-exports).

/// VDS header: emblem | dual-language country title | flag.
class _VdsHeader extends StatelessWidget {
  const _VdsHeader();

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const _VdsEmblem(size: 30),
        const SizedBox(width: 6),
        const Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ပြည်ထောင်စု သမ္မတ မြန်မာနိုင်ငံတော်',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _deepGreen,
                  fontSize: 11.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                'THE REPUBLIC OF THE UNION OF MYANMAR',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: _deepGreen,
                  fontSize: 7,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 6),
        const _VdsFlag(width: 36, height: 24),
      ],
    );
  }
}

/// State emblem: real PNG asset, painted ring+star fallback.
/// Keeps `Key('emblem')` for the layout tests either way.
class _VdsEmblem extends StatelessWidget {
  const _VdsEmblem({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: Image.asset(
        'assets/card/emblem.png',
        key: const Key('emblem'),
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const EmblemStandIn(size: 30, key: Key('emblem')),
      ),
    );
  }
}

/// National flag: real PNG asset, painted bands+star fallback.
/// Keeps `Key('flag')` for the layout tests either way.
class _VdsFlag extends StatelessWidget {
  const _VdsFlag({required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Image.asset(
        'assets/card/flag.png',
        key: const Key('flag'),
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) =>
            const MyanmarFlag(width: 36, height: 24, key: Key('flag')),
      ),
    );
  }
}

/// Card background: temple guilloche pattern extracted from the design
/// file (`docs/VDS Card.ai` → `assets/card/pattern_front/back.png`,
/// sample content filtered out), layered over the pale-green gradient
/// and the painted guilloche. If the asset is missing, the painted
/// pattern alone carries the theme — the card never breaks.
class _VdsBackground extends StatelessWidget {
  const _VdsBackground({required this.pattern});

  /// Asset path of the extracted temple pattern for this side.
  final String pattern;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Stack(
        fit: StackFit.expand,
        children: [
          const CustomPaint(painter: _GuillochePainter()),
          Image.asset(
            pattern,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => const SizedBox.shrink(),
          ),
        ],
      ),
    );
  }
}

/// Decorative bottom border: real strip PNG, geometric fallback.
/// The wrapper keeps `Key('border-strip')` for the layout tests.
class _VdsBorderStrip extends StatelessWidget {
  const _VdsBorderStrip();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      key: const Key('border-strip'),
      height: 9,
      width: double.infinity,
      child: Image.asset(
        'assets/card/border_strip.png',
        fit: BoxFit.fill,
        errorBuilder: (_, _, _) =>
            const CustomPaint(painter: _BorderStripPainter()),
      ),
    );
  }
}

/// Front: NRC layout per `id_layout_card.md`.
class _CardFront extends StatelessWidget {
  const _CardFront({required this.card, this.lift = 0});

  final CardData card;
  final double lift;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        borderRadius: _radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F8E9), Color(0xFFDCEDC8), Color(0xFFC5E1A5)],
        ),
        border: Border.all(color: _deepGreen, width: 1.2),
        boxShadow: [
          BoxShadow(
            blurRadius: 12 + 18 * lift,
            offset: Offset(0, 4 + 10 * lift),
            color: Colors.black.withValues(alpha: 0.15 + 0.22 * lift),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: Stack(
          children: [
            const _VdsBackground(pattern: 'assets/card/pattern_front.png'),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ---- Header: emblem | country | flag (VDS) ----
                  const _VdsHeader(),
                  const SizedBox(height: 4),
                  // ---- Body: info text col + QR col (QR fills its
                  // box — no loose white space around it) ----
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const _FrontLabel('အမည် / Name'),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      card.name.isEmpty ? '—' : card.name,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 15,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  const _FrontLabel('UID No.'),
                                  FittedBox(
                                    fit: BoxFit.scaleDown,
                                    alignment: Alignment.centerLeft,
                                    child: Text(
                                      card.uid,
                                      maxLines: 1,
                                      style: const TextStyle(
                                        color: _ink,
                                        fontSize: 12.5,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  const _FrontLabel(
                                    'နိုင်ငံသားစိစစ်ရေးကတ်ပြားအမှတ်',
                                  ),
                                  Text(
                                    card.nationalReg.isEmpty
                                        ? '—'
                                        : card.nationalReg,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: _ink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            QrImageView(
                              data: card.qrText,
                              version: QrVersions.auto,
                              errorCorrectionLevel: QrErrorCorrectLevel.L,
                              size: 96,
                              backgroundColor: Colors.white,
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Expanded(
                              child: _DateCell(
                                label: 'Date Of Birth',
                                value: fmtDateLong(card.dob),
                              ),
                            ),
                            const Expanded(
                              child: _DateCell(label: 'Gender', value: '—'),
                            ),
                            Expanded(
                              child: _DateCell(
                                label: 'Date Of Expiry',
                                value: card.exp == null
                                    ? '—'
                                    : fmtEpochLong(card.exp!),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const _VdsBorderStrip(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _FrontLabel extends StatelessWidget {
  const _FrontLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: const TextStyle(color: Colors.black, fontSize: 8.5),
    );
  }
}

class _DateCell extends StatelessWidget {
  const _DateCell({required this.label, required this.value});
  final String label;
  final String value;
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black54, fontSize: 8),
        ),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Text(
            value,
            maxLines: 1,
            style: const TextStyle(
              color: _ink,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------- painters

/// Pale-green guilloche: faint concentric-ring grid + wave lines.
class _GuillochePainter extends CustomPainter {
  const _GuillochePainter();

  @override
  void paint(Canvas canvas, Size size) {
    final ring = Paint()
      ..color = _deepGreen.withValues(alpha: 0.05)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.7;
    const step = 34.0;
    for (var cy = -step; cy < size.height + step; cy += step) {
      for (var cx = -step; cx < size.width + step; cx += step) {
        for (var r = 6.0; r <= 18.0; r += 6.0) {
          canvas.drawCircle(Offset(cx, cy), r, ring);
        }
      }
    }
    final wave = Paint()
      ..color = _deepGreen.withValues(alpha: 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.8;
    for (var k = 0; k < 3; k++) {
      final path = Path();
      final yBase = size.height * (0.3 + 0.2 * k);
      path.moveTo(0, yBase);
      for (var x = 0.0; x <= size.width; x += 8) {
        path.lineTo(x, yBase + 5 * sin(x / 22 + k));
      }
      canvas.drawPath(path, wave);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Repeating geometric border strip (deep green + gold diamonds).
class _BorderStripPainter extends CustomPainter {
  const _BorderStripPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = _deepGreen.withValues(alpha: 0.12),
    );
    final gold = Paint()..color = const Color(0xFFB8860B);
    final green = Paint()..color = _deepGreen;
    const w = 14.0;
    var i = 0;
    for (var x = 0.0; x < size.width; x += w, i++) {
      final cx = x + w / 2;
      final diamond = Path()
        ..moveTo(cx, 1)
        ..lineTo(cx + 4, h / 2)
        ..lineTo(cx, h - 1)
        ..lineTo(cx - 4, h / 2)
        ..close();
      canvas.drawPath(diamond, i.isEven ? green : gold);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Myanmar national flag: yellow/green/red bands + centred white star.
class MyanmarFlag extends StatelessWidget {
  const MyanmarFlag({super.key, required this.width, required this.height});

  final double width;
  final double height;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(border: Border.all(color: Colors.black26)),
      child: CustomPaint(painter: const _MyanmarFlagPainter()),
    );
  }
}

class _MyanmarFlagPainter extends CustomPainter {
  const _MyanmarFlagPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final band = size.height / 3;
    canvas.drawRect(
      Rect.fromLTWH(0, 0, size.width, band),
      Paint()..color = const Color(0xFFFECB00),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, band, size.width, band),
      Paint()..color = const Color(0xFF34B06B),
    );
    canvas.drawRect(
      Rect.fromLTWH(0, 2 * band, size.width, band),
      Paint()..color = const Color(0xFFEA2839),
    );
    final c = Offset(size.width / 2, size.height / 2);
    final rOuter = size.height * 0.30;
    final rInner = rOuter * 0.382;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final r = i.isEven ? rOuter : rInner;
      final a = -pi / 2 + i * pi / 5;
      final p = Offset(c.dx + r * cos(a), c.dy + r * sin(a));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

/// Stand-in state emblem: gold ring + star. Replace with official
/// artwork when available — do not mistake this for the real seal.
class EmblemStandIn extends StatelessWidget {
  const EmblemStandIn({super.key, required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(painter: _EmblemPainter()),
    );
  }
}

class _EmblemPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final c = Offset(size.width / 2, size.height / 2);
    final r = size.width / 2;
    canvas.drawCircle(
      c,
      r - 1,
      Paint()
        ..color = const Color(0xFFB8860B)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.6,
    );
    canvas.drawCircle(
      c,
      r * 0.72,
      Paint()..color = _deepGreen.withValues(alpha: 0.15),
    );
    final sr = r * 0.42;
    final star = Path();
    for (var i = 0; i < 10; i++) {
      final rr = i.isEven ? sr : sr * 0.382;
      final a = -pi / 2 + i * pi / 5;
      final p = Offset(c.dx + rr * cos(a), c.dy + rr * sin(a));
      if (i == 0) {
        star.moveTo(p.dx, p.dy);
      } else {
        star.lineTo(p.dx, p.dy);
      }
    }
    star.close();
    canvas.drawPath(star, Paint()..color = const Color(0xFFB8860B));
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ------------------------------------------------------------------ back

/// Back: mirrors the VDS back mock (`docs/VDS Card Back ( Ready To Print
/// ).png`) — full VDS header, verification trail in the left block
/// (where the mock prints the instruction paragraphs) beside the UID /
/// reference block on the right (where the mock shows UID + barcode +
/// signature), then the decorative border.
///
/// Info only: no portrait, no QR (it lives on the front), no MRZ lines,
/// no fabricated barcode or signature — the reference block shows the
/// UID text, issuer, and validity beside an italic verification line.
class _CardBack extends StatelessWidget {
  const _CardBack({
    required this.card,
    required this.faceMatch,
    required this.visualCheck,
    required this.externalFinger,
    this.lift = 0,
  });

  final CardData card;
  final FaceMatchResult? faceMatch;
  final bool visualCheck;
  final FingerMatch? externalFinger;
  final double lift;

  String _faceLine() {
    if (visualCheck) return 'FACE: VISUAL CHECK';
    return switch (faceMatch?.status) {
      FaceMatchStatus.match => 'FACE MATCH ✓',
      FaceMatchStatus.mismatch => 'FACE MISMATCH ✗',
      FaceMatchStatus.noFace => 'NO FACE ✗',
      _ => 'FACE —',
    };
  }

  bool get _faceOk => visualCheck || faceMatch?.status == FaceMatchStatus.match;

  @override
  Widget build(BuildContext context) {
    final finger = externalFinger;
    return Container(
      decoration: BoxDecoration(
        borderRadius: _radius,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFFF1F8E9), Color(0xFFDCEDC8), Color(0xFFC5E1A5)],
        ),
        border: Border.all(color: _deepGreen, width: 1.2),
        boxShadow: [
          BoxShadow(
            blurRadius: 12 + 18 * lift,
            offset: Offset(0, 4 + 10 * lift),
            color: Colors.black.withValues(alpha: 0.15 + 0.22 * lift),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: _radius,
        child: Stack(
          children: [
            const _VdsBackground(pattern: 'assets/card/pattern_back.png'),
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const _VdsHeader(),
                  const SizedBox(height: 6),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 7,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              _GreenTrailRow(
                                label: 'QR authentic (offline)',
                                pass: true,
                              ),
                              _GreenTrailRow(label: _faceLine(), pass: _faceOk),
                              _GreenTrailRow(
                                label: finger == null
                                    ? 'Fingerprint: skipped (optional)'
                                    : 'Fingerprint: ${finger.matched ? 'MATCH ✓' : 'MISMATCH ✗'}',
                                pass: finger?.matched ?? false,
                              ),
                              const SizedBox(height: 4),
                              Text(
                                card.biometricNote,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          flex: 4,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              FittedBox(
                                fit: BoxFit.scaleDown,
                                alignment: Alignment.centerLeft,
                                child: Text(
                                  card.uid,
                                  maxLines: 1,
                                  style: const TextStyle(
                                    color: _ink,
                                    fontSize: 14,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 2,
                                  ),
                                ),
                              ),
                              Container(
                                height: 1.5,
                                color: _deepGreen.withValues(alpha: 0.5),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                card.issuer,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  color: _ink,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              const Text(
                                'Verified fully offline',
                                style: TextStyle(
                                  color: _ink,
                                  fontSize: 10.5,
                                  fontStyle: FontStyle.italic,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                card.exp == null
                                    ? '—'
                                    : fmtEpochLong(card.exp!),
                                style: const TextStyle(
                                  color: Colors.black54,
                                  fontSize: 9.5,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  const _VdsBorderStrip(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GreenTrailRow extends StatelessWidget {
  const _GreenTrailRow({required this.label, required this.pass});
  final String label;
  final bool pass;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.zero,
      child: Row(
        children: [
          Icon(
            pass ? Icons.check_circle : Icons.radio_button_unchecked,
            size: 13,
            color: pass ? _deepGreen : Colors.black38,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: _ink, fontSize: 11),
            ),
          ),
        ],
      ),
    );
  }
}
