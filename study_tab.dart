import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'native.dart';
import 'session_screen.dart';
import 'store.dart';
import 'summary_screen.dart';
import 'theme.dart';
import 'widgets.dart';

class StudyTab extends ConsumerStatefulWidget {
  const StudyTab({super.key});
  @override
  ConsumerState<StudyTab> createState() => _StudyTabState();
}

class _StudyTabState extends ConsumerState<StudyTab> {
  String subject = 'Medicine', mode = 'Reading';
  int minutes = 25;
  bool camera = true;
  final goal = TextEditingController();

  void snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<void> _pickDate(bool ini) async {
    final st = ref.read(storeProvider);
    final d = await showDatePicker(
      context: context,
      initialDate: ini ? st.iniCet : st.neetPg,
      firstDate: DateTime(2026), lastDate: DateTime(2030),
      helpText: ini ? 'INI-CET date' : 'NEET PG date',
    );
    if (d != null) st.setExam(ini, d);
  }

  Future<void> _start() async {
    final st = ref.read(storeProvider);
    final lock = await Native.lockStatus();
    if (lock.active) { snack('A lockdown is active. Finish it or use the Guardian PIN first.'); return; }
    if (!await Native.isA11yEnabled() || !await Native.canOverlay()) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Blocker is off'),
          content: const Text('Accessibility or "Display over other apps" is not allowed, so other apps will NOT be fully restricted during this block. Continue anyway?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (st.strict && !st.hasPin) {
      if (!mounted) return;
      final go = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('No Guardian PIN'),
          content: const Text('End-early is locked down, and no PIN is set, so you will NOT be able to end this block early. Continue?'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
            TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Continue')),
          ],
        ),
      );
      if (go != true) return;
    }
    if (camera) {
      final ok = await showDialog<bool>(context: context, builder: (_) => CameraPreviewDialog(front: st.front));
      if (ok != true) return;
    }
    final cfg = SessionConfig(
      subject: subject, mode: mode, goal: goal.text.trim(), minutes: minutes,
      camera: camera, front: st.front, intervalSec: st.interval, strict: st.strict,
    );
    if (!mounted) return;
    final res = await Navigator.push<SessionResult>(context, MaterialPageRoute(builder: (_) => SessionScreen(cfg: cfg)));
    if (res != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => SummaryScreen(res: res)));
      goal.clear();
    }
  }

  Future<void> _quickLock(int hours) async {
    final st = ref.read(storeProvider);
    if (st.apps.isEmpty) { snack('Pick distraction apps first.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Lock for ${hours}h?'),
        content: Text('${st.apps.length} apps will be closed on sight. This can only be undone with the Guardian PIN.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('Lock it')),
        ],
      ),
    );
    if (ok == true) {
      await Native.startLock(hours * 3600 * 1000, st.apps, st.nuclear);
      if (mounted) snack('Locked for ${hours}h.');
    }
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storeProvider);
    final goalMin = st.goalH * 60;
    final today = st.todayMin;
    final now = DateTime.now();
    int left(DateTime d) => d.difference(DateTime(now.year, now.month, now.day)).inDays;

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Row(children: [
        Expanded(child: Text('FocusGuard', style: hs(28))),
        Text(st.rank, style: cap(w: FontWeight.w800, color: C.tangerine)),
      ]),
      const SizedBox(height: 12),
      Row(children: [
        Expanded(child: Bento(color: C.sky, margin: EdgeInsets.zero, onTap: () => _pickDate(true),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('INI-CET', style: cap(w: FontWeight.w700)),
              Text('${left(st.iniCet)} days', style: hs(24)),
            ]))),
        const SizedBox(width: 12),
        Expanded(child: Bento(color: C.peach, margin: EdgeInsets.zero, onTap: () => _pickDate(false),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('NEET PG', style: cap(w: FontWeight.w700)),
              Text('${left(st.neetPg)} days', style: hs(24)),
            ]))),
      ]),
      const SizedBox(height: 14),
      const LockBanner(),
      const A11yWarn(),

      // today's progress
      Bento(
        color: C.sage,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text("Today's Study Progress", style: hs(18))),
            Sel('Duty Day', st.duty, () => st.setDuty(true), onColor: C.leaf),
            const SizedBox(width: 6),
            Sel('Off Day', !st.duty, () => st.setDuty(false), onColor: C.leaf),
          ]),
          const SizedBox(height: 14),
          Bar(today / goalMin, color: today >= goalMin ? C.leaf : C.tangerine),
          const SizedBox(height: 8),
          Text('${hm(today)} of ${hm(goalMin)} goal${today >= goalMin ? '  ✓ done' : ''}', style: cap(color: C.ink, w: FontWeight.w700)),
        ]),
      ),

      // setup
      Bento(
        color: C.peach,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Study Setup', style: hs(18)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final s in subjectsAll) Sel(s, subject == s, () => setState(() => subject = s), onColor: C.tangerine),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final m in studyModes) Sel(m, mode == m, () => setState(() => mode = m)),
          ]),
          const SizedBox(height: 14),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final d in durations) Sel(durLabel(d), minutes == d, () => setState(() => minutes = d), onColor: C.night),
          ]),
          const SizedBox(height: 14),
          TextField(
            controller: goal, maxLength: 80,
            decoration: const InputDecoration(hintText: 'Goal in one line (e.g. Nephrotic syndrome MCQs)', counterText: ''),
          ),
        ]),
      ),

      // mode
      Bento(
        color: C.sky,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(camera ? 'AI Camera Proctor' : 'Phone-Study Lock', style: hs(18)),
          const SizedBox(height: 4),
          Text(camera
              ? 'Prop the phone so it sees your face and your book. Your face must stay visible and live, and no other device may be in view. 100% on-device, frames deleted instantly, flash never fires.'
              : 'Study on Marrow / PrepLadder / Anki. No camera.',
              style: cap(color: C.ink)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, children: [
            Sel('📷 Camera Proctor', camera, () => setState(() => camera = true)),
            Sel('📱 Phone Lock', !camera, () => setState(() => camera = false)),
          ]),
          const SizedBox(height: 12),
          if (camera) ...[
            Wrap(spacing: 6, runSpacing: 6, children: [
              Sel('Back camera', !st.front, () => st.setFront(false)),
              Sel('Front camera', st.front, () => st.setFront(true)),
            ]),
            const SizedBox(height: 10),
            Wrap(spacing: 6, runSpacing: 6, children: [
              for (final s in [15, 30, 60, 120]) Sel('every ${s}s', st.interval == s, () => st.setInterval(s)),
            ]),
            const SizedBox(height: 10),
            Text(
              st.calibrating
                  ? '📊 Calibration day: no lives are lost today. Today\'s distractions set your baseline.'
                  : '❤️ Lives for this ${durLabel(minutes)} block: ${st.livesFor(minutes)} (50% of your Day-1 distractions)',
              style: cap(color: C.ink, w: FontWeight.w700),
            ),
            const SizedBox(height: 12),
          ],
          Row(children: [
            Expanded(
              child: Text('${st.allowedApps.length} study apps allowed\nEverything else is locked while the timer runs.',
                  style: cap(color: C.ink, w: FontWeight.w700)),
            ),
            InkBtn('Pick apps', onTap: () async {
              final r = await showModalBottomSheet<List<String>>(
                  context: context, isScrollControlled: true, backgroundColor: C.cream,
                  builder: (_) => AppPicker(title: 'Pick allowed study apps', selected: st.allowedApps));
              if (r != null) st.setAllowedApps(r);
            }),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
            title: const Text('🔒 Lock down End early', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(st.hasPin
                ? 'Ending a block early will need the Guardian PIN'
                : 'Set a Guardian PIN in Rules first, or you cannot end early at all',
                style: cap(color: C.ink)),
            value: st.strict, onChanged: st.setStrict,
          ),
        ]),
      ),

      InkBtn('Start ${durLabel(minutes)} block', icon: Icons.play_arrow_rounded, wide: true, onTap: _start, bg: C.tangerine),
      const SizedBox(height: 18),

      // quick lock
      Bento(
        color: C.night,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Quick Strict Lock', style: hs(18, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Instant lockdown of your distraction apps. No camera. Only the Guardian PIN can lift it.',
              style: cap(color: Colors.white60)),
          const SizedBox(height: 12),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final h in [1, 2, 4, 8, 12, 24]) Sel('${h}h', false, () => _quickLock(h), dark: true),
          ]),
        ]),
      ),
    ]);
  }
}

/// Live framing preview before a camera session. Flash forced off.
class CameraPreviewDialog extends StatefulWidget {
  final bool front;
  const CameraPreviewDialog({super.key, required this.front});
  @override
  State<CameraPreviewDialog> createState() => _CameraPreviewDialogState();
}

class _CameraPreviewDialogState extends State<CameraPreviewDialog> {
  CameraController? _c;
  String? err;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final dir = widget.front ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = cams.firstWhere((c) => c.lensDirection == dir, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      if (!mounted) { await c.dispose(); return; }
      setState(() => _c = c);
    } catch (e) {
      if (mounted) setState(() => err = 'Camera unavailable. Allow camera permission and try again.');
    }
  }

  @override
  void dispose() { _c?.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: C.cream,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Frame yourself', style: hs(20)),
          Text('Make sure your face or hands and desk are visible.', style: cap()),
          const SizedBox(height: 12),
          if (err != null)
            Padding(padding: const EdgeInsets.all(20), child: Text(err!, style: cap(color: C.crimson)))
          else if (_c == null)
            const Padding(padding: EdgeInsets.all(40), child: CircularProgressIndicator())
          else
            ClipRRect(
              borderRadius: BorderRadius.circular(20),
              child: SizedBox(height: 320, child: AspectRatio(aspectRatio: 1 / _c!.value.aspectRatio, child: CameraPreview(_c!))),
            ),
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel'))),
            Expanded(child: InkBtn('Looks good', onTap: _c == null ? null : () => Navigator.pop(context, true))),
          ]),
        ]),
      ),
    );
  }
}
