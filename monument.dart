import 'package:flutter/material.dart';
import 'theme.dart';

/// Foundation -> Pillars -> Study Halls -> High-Yield Spire -> Golden Crown.
/// Rule-breaks leave crimson cracks (repaired by clean >=90% focus blocks).
class MonumentPainter extends CustomPainter {
  final double progress;
  final int cracks;
  MonumentPainter(this.progress, this.cracks);

  double _seg(double a, double b) => ((progress - a) / (b - a)).clamp(0.0, 1.0).toDouble();

  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final ground = h * 0.93;
    final fill = Paint()..style = PaintingStyle.fill;
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 2..color = const Color(0xFF3C322D);

    void box(Rect r, Color col, [double rad = 4]) {
      final rr = RRect.fromRectAndRadius(r, Radius.circular(rad));
      fill.color = col;
      c.drawRRect(rr, fill);
      c.drawRRect(rr, line);
    }

    // grass strip
    fill.color = const Color(0xFFB9D7A5);
    c.drawRRect(RRect.fromRectAndRadius(Rect.fromLTWH(0, ground, w, h - ground), const Radius.circular(8)), fill);

    final fH = h * 0.09, pMax = h * 0.28, hallMax = h * 0.2, spMax = h * 0.2;
    final f = _seg(0.0, 0.2), p = _seg(0.2, 0.45), hl = _seg(0.45, 0.7);
    final sp = _seg(0.7, 0.9), cr = _seg(0.9, 1.0);
    final fTop = ground - fH * f;

    if (f > 0) {
      box(Rect.fromLTWH(w * 0.1, fTop, w * 0.8, fH * f), const Color(0xFFCFC8B8));
      if (f > 0.5) box(Rect.fromLTWH(w * 0.16, fTop - fH * 0.4 * f, w * 0.68, fH * 0.4 * f), const Color(0xFFDAD3C3));
    }
    final baseY = ground - fH - fH * 0.4;
    if (p > 0) {
      for (int i = 0; i < 4; i++) {
        final x = w * (0.2 + 0.19 * i);
        box(Rect.fromLTWH(x, baseY - pMax * p, w * 0.07, pMax * p), const Color(0xFFEFE9DA), 3);
      }
    }
    final pTop = baseY - pMax;
    if (hl > 0) {
      final r = Rect.fromLTWH(w * 0.2, pTop - hallMax * hl, w * 0.6, hallMax * hl);
      box(r, const Color(0xFFF7D9BC), 5);
      if (hl > 0.7) {
        fill.color = const Color(0xFFFFF2B0);
        for (int i = 0; i < 4; i++) {
          c.drawRRect(
              RRect.fromRectAndRadius(
                  Rect.fromLTWH(w * (0.26 + 0.135 * i), pTop - hallMax * 0.75, w * 0.07, hallMax * 0.35),
                  const Radius.circular(3)),
              fill);
        }
      }
    }
    final hTop = pTop - hallMax;
    if (sp > 0) {
      final path = Path()
        ..moveTo(w * 0.3, hTop)
        ..lineTo(w * 0.7, hTop)
        ..lineTo(w * 0.5, hTop - spMax * sp)
        ..close();
      fill.color = const Color(0xFF9CC3E0);
      c.drawPath(path, fill);
      c.drawPath(path, line);
    }
    final sTop = hTop - spMax;
    if (cr > 0) {
      final cw = w * 0.2, chh = h * 0.08 * cr, cx = w * 0.5, cy = sTop;
      final crown = Path()
        ..moveTo(cx - cw / 2, cy)
        ..lineTo(cx - cw / 2, cy - chh)
        ..lineTo(cx - cw / 4, cy - chh * 0.5)
        ..lineTo(cx, cy - chh * 1.1)
        ..lineTo(cx + cw / 4, cy - chh * 0.5)
        ..lineTo(cx + cw / 2, cy - chh)
        ..lineTo(cx + cw / 2, cy)
        ..close();
      fill.color = const Color(0xFFEBB93D);
      c.drawPath(crown, fill);
      c.drawPath(crown, line);
    }

    // cracks
    final crack = Paint()..style = PaintingStyle.stroke..strokeWidth = 3
      ..strokeCap = StrokeCap.round..color = C.crimson;
    for (int k = 0; k < cracks; k++) {
      final x = w * (0.26 + 0.16 * k);
      final y0 = ground - 2;
      final path = Path()
        ..moveTo(x, y0)
        ..lineTo(x + 6, y0 - 12)
        ..lineTo(x - 3, y0 - 22)
        ..lineTo(x + 7, y0 - 34)
        ..lineTo(x, y0 - 46);
      c.drawPath(path, crack);
    }
  }

  @override
  bool shouldRepaint(MonumentPainter o) => o.progress != progress || o.cracks != cracks;
}

class MonumentView extends StatelessWidget {
  final double progress;
  final int cracks;
  final double height;
  final Color textColor;
  const MonumentView(this.progress, this.cracks, {super.key, this.height = 170, this.textColor = C.ink});

  String get stage {
    if (progress >= 1) return 'Golden Crown ✨';
    if (progress >= 0.9) return 'Crowning';
    if (progress >= 0.7) return 'High-Yield Spire';
    if (progress >= 0.45) return 'Study Halls';
    if (progress >= 0.2) return 'Pillars';
    return 'Foundation';
  }

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: const Duration(milliseconds: 1200),
        curve: Curves.easeOutCubic,
        builder: (_, v, __) => Column(children: [
          SizedBox(height: height, width: double.infinity,
              child: CustomPaint(painter: MonumentPainter(v, cracks))),
          const SizedBox(height: 8),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('${(v * 100).round()}%', style: hs(22, color: textColor)),
            Text(cracks > 0 ? '$stage · $cracks crack${cracks > 1 ? 's' : ''} 💔' : stage,
                style: cap(color: textColor.withOpacity(0.75), w: FontWeight.w700)),
          ]),
        ]),
      );
}
