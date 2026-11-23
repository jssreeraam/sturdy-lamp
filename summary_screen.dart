import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'monument.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class SummaryScreen extends ConsumerStatefulWidget {
  final SessionResult res;
  const SummaryScreen({super.key, required this.res});
  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  late final TextEditingController log;
  final mcqT = TextEditingController(), mcqC = TextEditingController(), gt = TextEditingController();
  bool hy = false, saving = false;
  late final int xp;

  SessionResult get r => widget.res;
  bool get combo => r.focus >= 90 && !r.failed;

  @override
  void initState() {
    super.initState();
    log = TextEditingController(text: r.cfg.goal);
    final base = (r.durationSec / 60).round() * 2;
    xp = r.failed ? 0 : ((base * r.focus / 100).round() * (combo ? 2 : 1));
  }

  Future<void> _save() async {
    setState(() => saving = true);
    final st = ref.read(storeProvider);
    final text = log.text.trim();
    final ss = Session(
      startMs: r.start.millisecondsSinceEpoch, durationSec: r.durationSec, plannedMin: r.cfg.minutes,
      subject: r.cfg.subject, mode: r.cfg.mode, kind: r.cfg.camera ? 'camera' : 'phone', goal: text,
      focus: r.focus, tokens: r.tokens, failed: r.failed, distractions: r.distractions,
      mcqTotal: int.tryParse(mcqT.text) ?? 0, mcqCorrect: int.tryParse(mcqC.text) ?? 0,
      gt: int.tryParse(gt.text)?.clamp(0, 200).toInt(), highYield: hy, xp: xp, hardcore: r.cfg.hardcore,
    );
    await st.addSession(ss);
    if (text.isNotEmpty && r.durationSec >= 300) {
      await st.addRevision(text, r.cfg.subject, hy); // auto-scheduled into Spaced Repetition
    }
    if (mounted) Navigator.pop(context);
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storeProvider);
    final extra = r.durationSec / 60.0;
    final prog = st.monthProgress(extraMin: extra);
    return PopScope(
      canPop: false,
      child: Scaffold(
        body: SafeArea(
          child: ListView(padding: const EdgeInsets.all(16), children: [
            Bento(
              color: r.failed ? const Color(0xFFF8D7D2) : C.sage,
              child: Column(children: [
                Text(r.failed ? 'Block broken 💔' : (combo ? '2× Combo! 🔥' : 'Block complete ✓'), style: hs(24)),
                const SizedBox(height: 8),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: xp.toDouble()),
                  duration: const Duration(milliseconds: 1400),
                  curve: Curves.easeOutCubic,
                  builder: (_, v, __) => Text('+${v.round()} XP', style: hs(46, color: C.tangerine)),
                ),
                const SizedBox(height: 6),
                Text('${hm(r.durationSec / 60)}  ·  ${r.focus}% focus${r.cfg.camera ? (r.maxLives > 0 ? '  ·  ${r.tokens}/${r.maxLives} lives' : '  ·  ${r.distractions} distractions (calibration)') : ''}',
                    style: cap(color: C.ink, w: FontWeight.w700, size: 14)),
              ]),
            ),
            Bento(
              color: C.lavender,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Study Log', style: hs(18)),
                Text('Saved to Spaced Repetition (Day +1 → +3 → +7 → +21 → +45)', style: cap()),
                const SizedBox(height: 10),
                TextField(controller: log, maxLength: 80, decoration: const InputDecoration(hintText: 'What did you cover?', counterText: '')),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
                  title: const Text('High-Yield ★', style: TextStyle(fontWeight: FontWeight.w800)),
                  subtitle: const Text('Pin to the top of revisions'),
                  value: hy, onChanged: (v) => setState(() => hy = v),
                ),
              ]),
            ),
            Bento(
              color: C.butter,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.cfg.mode == 'Grand Test' ? 'GT Score & MCQs' : 'MCQs (optional)', style: hs(18)),
                const SizedBox(height: 10),
                Row(children: [
                  Expanded(child: TextField(controller: mcqT, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Solved'))),
                  const SizedBox(width: 10),
                  Expanded(child: TextField(controller: mcqC, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'Correct'))),
                ]),
                if (r.cfg.mode == 'Grand Test') ...[
                  const SizedBox(height: 10),
                  TextField(controller: gt, keyboardType: TextInputType.number, decoration: const InputDecoration(hintText: 'GT score (/200)')),
                ],
              ]),
            ),
            Bento(
              color: C.sage,
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Monthly Citadel', style: hs(18)),
                const SizedBox(height: 10),
                MonumentView(prog, st.cracks + (r.failed ? 1 : 0), height: 150),
              ]),
            ),
            InkBtn(saving ? 'Saving…' : 'Save & finish', wide: true, onTap: saving ? null : _save),
          ]),
        ),
      ),
    );
  }
}
