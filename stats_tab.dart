import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'monument.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class StatsTab extends ConsumerWidget {
  const StatsTab({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider);
    final today = st.todayNum;
    final info = st.streakInfo();
    final goalMin = st.goalH * 60;

    // today's snapshot
    final todays = st.sessions.where((s) => dayNum(DateTime.fromMillisecondsSinceEpoch(s.startMs)) == today).toList();
    final tMin = todays.fold<double>(0, (a, s) => a + s.minutes);
    final tFocus = tMin == 0 ? 0 : (todays.fold<double>(0, (a, s) => a + s.focus * s.minutes) / tMin).round();
    final tMcq = todays.fold<int>(0, (a, s) => a + s.mcqTotal);
    final hours = st.hourMinutesOn(today);

    // 30 day
    final days = [for (int i = 29; i >= 0; i--) today - i];
    final mins = {for (final d in days) d: st.minutesOn(d)};
    final week = days.sublist(23);

    final subj = st.subjectMinutes(30);
    final subjSorted = subj.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final subjMax = subjSorted.isEmpty ? 1.0 : subjSorted.first.value;

    final gts = st.sessions.where((s) => s.gt != null).toList();
    final gtPts = gts.length > 15 ? gts.sublist(gts.length - 15) : gts;

    final (hMin, hW) = st.hourFocus();
    int? best, worst;
    double bestV = -1, worstV = 2;
    for (int h = 0; h < 24; h++) {
      if (hMin[h] < 15) continue;
      final v = hW[h] / hMin[h];
      if (v > bestV) { bestV = v; best = h; }
      if (v < worstV) { worstV = v; worst = h; }
    }
    String hr(int h) => '${h % 12 == 0 ? 12 : h % 12}${h < 12 ? 'AM' : 'PM'}';

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Text('Stats', style: hs(28)),
      const SizedBox(height: 14),

      Bento(
        color: C.sage,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Monthly Citadel', style: hs(18)),
          Text('Study this month to build it. Cracks repair with a clean ≥90% focus block.', style: cap()),
          const SizedBox(height: 10),
          MonumentView(st.monthProgress(), st.cracks),
        ]),
      ),

      Bento(
        color: C.butter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text(st.rank, style: hs(20))),
            Text('${st.totalXp} XP', style: hs(16, color: C.tangerine)),
          ]),
          const SizedBox(height: 8),
          Bar(st.tierProgress, color: C.tangerine),
          const SizedBox(height: 12),
          Text('🔥 ${info.streak}-day streak   🛡️ ${info.shields}/2 shields', style: cap(color: C.ink, w: FontWeight.w800, size: 14)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final b in st.badges)
              Tooltip(
                message: b.hint,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: b.earned ? Colors.white : Colors.white30,
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Opacity(
                    opacity: b.earned ? 1 : 0.4,
                    child: Text('${b.emoji} ${b.title}', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13)),
                  ),
                ),
              ),
          ]),
        ]),
      ),

      Bento(
        color: C.sky,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text("Today's Snapshot", style: hs(18)),
          const SizedBox(height: 10),
          Row(children: [
            _stat('Studied', hm(tMin)),
            _stat('Focus', tMin == 0 ? '–' : '$tFocus%'),
            _stat('Blocks', '${todays.length}'),
            _stat('MCQs', '$tMcq'),
          ]),
          const SizedBox(height: 14),
          Text('24-hour timeline', style: cap(w: FontWeight.w700)),
          const SizedBox(height: 6),
          Row(children: [
            for (int h = 0; h < 24; h++)
              Expanded(
                child: Container(
                  height: 26, margin: const EdgeInsets.symmetric(horizontal: 1),
                  decoration: BoxDecoration(
                    color: Color.lerp(Colors.white54, C.tangerine, (hours[h] / 60).clamp(0.0, 1.0).toDouble()),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [for (final t in ['12a', '6a', '12p', '6p', '12a']) Text(t, style: cap(size: 11))]),
        ]),
      ),

      Bento(
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('30-Day Consistency', style: hs(18)),
          const SizedBox(height: 10),
          Wrap(spacing: 4, runSpacing: 4, children: [
            for (final d in days)
              Tooltip(
                message: '${fmtDay(d)}: ${hm(mins[d]!)}',
                child: Container(
                  width: 28, height: 28,
                  decoration: BoxDecoration(
                    color: Color.lerp(const Color(0xFFEDEBE3), C.leaf, (mins[d]! / goalMin).clamp(0.0, 1.0).toDouble()),
                    borderRadius: BorderRadius.circular(8),
                    border: d == today ? Border.all(color: C.ink, width: 2) : null,
                  ),
                ),
              ),
          ]),
          const SizedBox(height: 18),
          Text('7-Day Goal Chart', style: hs(16)),
          const SizedBox(height: 8),
          SizedBox(
            height: 120,
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (final d in week)
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text(mins[d]! < 1 ? '' : (mins[d]! / 60).toStringAsFixed(1), style: cap(size: 10)),
                    const SizedBox(height: 2),
                    Container(
                      height: max(4.0, 84 * (mins[d]! / max(goalMin, mins[d]!))),
                      margin: const EdgeInsets.symmetric(horizontal: 5),
                      decoration: BoxDecoration(
                        color: mins[d]! >= goalMin ? C.leaf : C.tangerine.withOpacity(0.55),
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text('${dayDate(d).day}', style: cap(size: 11)),
                  ]),
                ),
            ]),
          ),
          Text('Green = daily goal hit (${hm(goalMin)})', style: cap(size: 11)),
        ]),
      ),

      Bento(
        color: C.peach,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Neglected Subject Radar', style: hs(18)),
          Text('Red = untouched for 14+ days', style: cap()),
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in subjects19) _radarPill(s, st.daysSince(s)),
          ]),
        ]),
      ),

      Bento(
        color: C.lavender,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('30-Day Subject Breakdown', style: hs(18)),
          const SizedBox(height: 10),
          if (subjSorted.isEmpty) Text('No sessions yet.', style: cap()),
          for (final e in subjSorted)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(children: [
                SizedBox(width: 92, child: Text(e.key, style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13))),
                Expanded(child: Bar(e.value / subjMax, color: C.tangerine, height: 10)),
                const SizedBox(width: 8),
                Text(hm(e.value), style: cap(size: 12, w: FontWeight.w700)),
              ]),
            ),
        ]),
      ),

      Bento(
        color: C.butter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Grand Test Trend (/200)', style: hs(18)),
          const SizedBox(height: 10),
          if (gtPts.length < 2)
            Text('Log 2+ Grand Test scores to see the trend.', style: cap())
          else
            SizedBox(height: 130, width: double.infinity, child: CustomPaint(painter: _Trend(gtPts.map((s) => s.gt!.toDouble()).toList()))),
        ]),
      ),

      Bento(
        color: C.sky,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Sharpest vs Weakest Hours', style: hs(18)),
          const SizedBox(height: 8),
          if (best == null) Text('Needs a few more focused blocks.', style: cap())
          else ...[
            Text('⚡ Sharpest: ${hr(best)}–${hr((best + 1) % 24)} (${(bestV * 100).round()}% focus)', style: cap(color: C.ink, size: 14, w: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('🌫️ Weakest: ${hr(worst!)}–${hr((worst + 1) % 24)} (${(worstV * 100).round()}% focus)', style: cap(color: C.ink, size: 14, w: FontWeight.w700)),
          ],
        ]),
      ),

      Bento(
        color: Colors.white,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Day-by-Day Study Log', style: hs(18)),
          const SizedBox(height: 8),
          ..._log(st, days),
        ]),
      ),
    ]);
  }

  static Widget _stat(String l, String v) => Expanded(
        child: Column(children: [Text(v, style: hs(20)), Text(l, style: cap(size: 12))]),
      );

  static Widget _radarPill(String s, int? d) {
    final Color bg = d == null || d >= 14 ? const Color(0xFFF4C7C0) : d >= 7 ? C.butter : C.sage;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(20)),
      child: Text('$s · ${d == null ? 'never' : '${d}d'}',
          style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: d == null || d >= 14 ? C.crimson : C.ink)),
    );
  }

  static List<Widget> _log(AppStore st, List<int> days) {
    final out = <Widget>[];
    for (final d in days.reversed) {
      final ss = st.sessions.where((s) => dayNum(DateTime.fromMillisecondsSinceEpoch(s.startMs)) == d).toList();
      if (ss.isEmpty) continue;
      final m = ss.fold<double>(0, (a, s) => a + s.minutes);
      final f = m == 0 ? 0 : (ss.fold<double>(0, (a, s) => a + s.focus * s.minutes) / m).round();
      final t = ss.fold<int>(0, (a, s) => a + s.mcqTotal), c = ss.fold<int>(0, (a, s) => a + s.mcqCorrect);
      final subs = ss.map((s) => s.subject).toSet().join(', ');
      final notes = ss.map((s) => s.goal).where((g) => g.isNotEmpty).join(' · ');
      out.add(Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('${fmtDay(d)}  ·  ${hm(m)}  ·  $f% focus${t > 0 ? '  ·  MCQ $c/$t' : ''}', style: const TextStyle(fontWeight: FontWeight.w800)),
          Text(subs, style: cap(color: C.ink)),
          if (notes.isNotEmpty) Text(notes, style: cap()),
        ]),
      ));
    }
    if (out.isEmpty) out.add(Text('Nothing logged yet.', style: cap()));
    return out;
  }
}

class _Trend extends CustomPainter {
  final List<double> v;
  _Trend(this.v);
  @override
  void paint(Canvas c, Size s) {
    final lo = max(0.0, v.reduce(min) - 15), hi = min(200.0, v.reduce(max) + 15);
    final span = max(1.0, hi - lo);
    Offset pt(int i) => Offset(8 + (s.width - 16) * i / (v.length - 1), s.height - 16 - (s.height - 32) * ((v[i] - lo) / span));
    final line = Paint()..style = PaintingStyle.stroke..strokeWidth = 3..color = C.tangerine..strokeCap = StrokeCap.round;
    final path = Path()..moveTo(pt(0).dx, pt(0).dy);
    for (int i = 1; i < v.length; i++) { path.lineTo(pt(i).dx, pt(i).dy); }
    c.drawPath(path, line);
    final dot = Paint()..color = C.ink;
    for (int i = 0; i < v.length; i++) { c.drawCircle(pt(i), 4, dot); }
    final tp = TextPainter(
        text: TextSpan(text: '${v.last.round()}', style: const TextStyle(color: C.ink, fontWeight: FontWeight.w800, fontSize: 13)),
        textDirection: TextDirection.ltr)
      ..layout();
    tp.paint(c, pt(v.length - 1) + const Offset(-8, -22));
  }
  @override
  bool shouldRepaint(_Trend o) => o.v != v;
}
