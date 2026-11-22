import 'dart:math';
import 'package:flutter/material.dart';
import 'theme.dart';

class StudyGirl extends StatefulWidget {
  final double progress, size;
  final bool running;
  const StudyGirl({super.key, required this.progress, this.running = true, this.size = 280});
  @override
  State<StudyGirl> createState() => _StudyGirlState();
}

class _StudyGirlState extends State<StudyGirl> with SingleTickerProviderStateMixin {
  late final AnimationController _a =
      AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat(reverse: true);
  @override
  void dispose() { _a.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _a,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_a.value);
        final glow = widget.running ? 0.22 + 0.22 * t : 0.1;
        return SizedBox(
          width: s, height: s,
          child: Stack(alignment: Alignment.center, children: [
            Container(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(colors: [C.tangerine.withOpacity(glow), Colors.transparent]),
              ),
            ),
            CustomPaint(size: Size.square(s), painter: _Ring(widget.progress)),
            Transform.translate(
              offset: Offset(0, widget.running ? -6 * t : 0),
              child: Padding(
                padding: EdgeInsets.all(s * 0.13),
                child: Image.asset('assets/study_girl.png', fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) =>
                        Icon(Icons.menu_book_rounded, size: s * 0.4, color: Colors.white54)),
              ),
            ),
          ]),
        );
      },
    );
  }
}

class _Ring extends CustomPainter {
  final double progress;
  _Ring(this.progress);
  @override
  void paint(Canvas c, Size s) {
    final rect = Rect.fromLTWH(8, 8, s.width - 16, s.height - 16);
    final track = Paint()..style = PaintingStyle.stroke..strokeWidth = 8
      ..color = Colors.white.withOpacity(0.14);
    final arc = Paint()..style = PaintingStyle.stroke..strokeWidth = 8
      ..strokeCap = StrokeCap.round..color = C.tangerine;
    c.drawArc(rect, 0, 2 * pi, false, track);
    c.drawArc(rect, -pi / 2, 2 * pi * progress.clamp(0.0, 1.0), false, arc);
  }
  @override
  bool shouldRepaint(_Ring o) => o.progress != progress;
}
