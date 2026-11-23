import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'girl.dart';
import 'theme.dart';
import 'vision.dart';
import 'widgets.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final SessionConfig cfg;
  const SessionScreen({super.key, required this.cfg});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  DateTime _start = DateTime.now();
  Timer? _tick, _shotTimer;
  int _elapsed = 0;
  VisionService? _vision;
  final _rng = Random();

  late final bool calibrating;
  late final int maxLives;
  int tokens = 0, nStudy = 0, nNeutral = 0, nBad = 0, distractions = 0, points = 0;
  bool _dim = false, _noise = false, _done = false, _ready = false, _locked = false;
  String _status = 'Preparing…';

  SessionConfig get cfg => widget.cfg;
  int get total => cfg.minutes * 60;

  @override
  void initState() {
    super.initState();
    final st = ref.read(storeProvider);
    calibrating = cfg.camera && st.calibrating;
    maxLives = (cfg.camera && !calibrating) ? st.livesFor(cfg.minutes) : 0;
    tokens = maxLives;
    _begin();
  }

  Future<void> _begin() async {
    final st = ref.read(storeProvider);
    Native.keepScreenOn(true);
    Native.scheduleSessionAlert(total * 1000);
    if (cfg.camera) {
      final ok = await _initCam();
      if (!ok) return;
    }
    // Whitelist lock: ONLY the allowed study apps (plus launcher, keyboard, dialer) work until the timer ends.
    await Native.startLock(total * 1000, st.allowedApps, false, allow: true);
    _locked = true;
    if (!cfg.camera) _status = 'Locked in. Go study.';
    _start = DateTime.now();
    _ready = true;
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      final e = DateTime.now().difference(_start).inSeconds; // drift-free
      if (!mounted || _done) return;
      setState(() => _elapsed = e);
      if (e >= total) _finish();
    });
    if (mounted) setState(() {});
  }

  Future<bool> _initCam() async {
    try {
      final v = VisionService();
      await v.init(front: cfg.front);
      _vision = v;
      _status = calibrating ? 'Calibration day: learning your focus pattern…' : 'Watching quietly…';
      _scheduleNext(first: true);
      return true;
    } catch (_) {
      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Camera unavailable'),
            content: const Text('Allow camera permission, or use Phone-Study Lock mode.'),
            actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('OK'))],
          ),
        );
        _done = true;
        _cleanup();
        if (mounted) Navigator.pop(context, null);
      }
      return false;
    }
  }

  /// Checks happen at RANDOM times around your chosen interval, so they can't be timed.
  /// The first check comes after ~8 seconds so you can see it working.
  void _scheduleNext({bool first = false}) {
    if (_done) return;
    final base = cfg.intervalSec;
    final secs = first ? 8 : (base * (0.6 + _rng.nextDouble() * 0.8)).round().clamp(5, 600).toInt();
    _shotTimer = Timer(Duration(seconds: secs), () async {
      await _check();
      _scheduleNext();
    });
  }

  Future<void> _check() async {
    final v = _vision;
    if (_done || v == null || !_ready) return;
    final s = await v.classify();
    if (_done || !mounted) return;
    final info = v.lastInfo;
    if (s == FocusState.study) {
      nStudy++; points += 2;
      _status = '$info · +2';
    } else if (s == FocusState.neutral) {
      nNeutral++;
      _status = info;
    } else {
      distractions++; nBad++;
      if (!calibrating) tokens--;
      Native.vibrate(s == FocusState.absent ? [0, 450] : [0, 120, 90, 120]);
      _status = '$info · ${calibrating ? 'calibration, no life lost' : '-1 life'}';
    }
    setState(() {});
    if (!calibrating && cfg.camera && tokens <= 0) _finish(failed: true);
  }

  int get _focus {
    final t = nStudy + nNeutral + nBad;
    return t == 0 ? 100 : (((nStudy + nNeutral) * 100) / t).round();
  }

  void _cleanup() {
    _tick?.cancel();
    _shotTimer?.cancel();
    _vision?.dispose();
    _vision = null;
    Native.keepScreenOn(false);
    Native.stopNoise();
    Native.cancelSessionAlert();
    if (_locked) { Native.clearLock(); _locked = false; }
  }

  Future<void> _finish({bool failed = false, bool abandoned = false, bool authorised = false}) async {
    if (_done) return;
    _done = true;
    final int secs = _ready ? DateTime.now().difference(_start).inSeconds.clamp(0, total).toInt() : 0;
    _cleanup();
    final penalise = abandoned && cfg.hardcore && !authorised;
    if (penalise) {
      final st = ref.read(storeProvider);
      await Native.startLock(2 * 3600 * 1000, st.apps, true); // 2h full lockdown for quitting a Hardcore GT
    }
    if (!mounted) return;
    if (abandoned && secs < 60) { Navigator.pop(context, null); return; }
    Navigator.pop(
      context,
      SessionResult(
        cfg: cfg, start: _start, durationSec: secs, focus: cfg.camera ? _focus : 100,
        tokens: tokens.clamp(0, maxLives).toInt(), maxLives: maxLives,
        distractions: distractions, failed: failed || penalise,
      ),
    );
  }

  void _snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _askPin() {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.cream,
        title: const Text('Guardian PIN'),
        content: TextField(
          controller: c, autofocus: true, obscureText: true, maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(hintText: '6-digit PIN', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _endEarly() async {
    final st = ref.read(storeProvider);
    if (cfg.strict) {
      if (!st.hasPin) { _snack('End-early is locked down. No Guardian PIN is set, so this block runs to the end.'); return; }
      final pin = await _askPin();
      if (pin == null) return;
      if (!st.checkPin(pin)) { _snack('Wrong PIN.'); return; }
      await st.bumpHonesty();
      _finish(abandoned: true, authorised: true);
      return;
    }
    final msg = cfg.hardcore
        ? 'Quitting a 180m Hardcore GT triggers a 2-hour full lockdown.'
        : 'Your progress so far will still be logged.';
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('End this block early?'),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Keep going')),
          TextButton(onPressed: () => Navigator.pop(context, true), child: const Text('End it')),
        ],
      ),
    );
    if (ok == true) _finish(abandoned: true);
  }

  @override
  void dispose() {
    if (!_done) { _done = true; _cleanup(); }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final remaining = total - _elapsed;
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: C.night,
        body: Stack(children: [
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [
                Row(children: [
                  Expanded(
                    child: Text('${cfg.subject} · ${cfg.mode}', style: hs(16, color: Colors.white70, w: FontWeight.w700)),
                  ),
                  if (cfg.camera)
                    Text(
                      calibrating ? '📊 Calibrating · $distractions' : '❤️ $tokens/$maxLives',
                      style: hs(16, color: Colors.white70, w: FontWeight.w700),
                    ),
                ]),
                const Spacer(),
                StudyGirl(progress: total == 0 ? 0 : _elapsed / total, running: _ready, size: 300),
                const SizedBox(height: 10),
                Text(mmss(remaining), style: hs(54, color: Colors.white)),
                const SizedBox(height: 6),
                Text(_status, textAlign: TextAlign.center, style: cap(color: Colors.white60, size: 14)),
                if (cfg.camera) ...[
                  const SizedBox(height: 4),
                  Text('⭐ $points focus points', style: cap(color: C.tangerine, size: 14, w: FontWeight.w800)),
                ],
                if (cfg.goal.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Text('🎯 ${cfg.goal}', textAlign: TextAlign.center, style: cap(color: Colors.white70, size: 15, w: FontWeight.w700)),
                ],
                const Spacer(),
                Wrap(spacing: 8, runSpacing: 8, alignment: WrapAlignment.center, children: [
                  Sel(_noise ? '🌊 Brown noise on' : '🌊 Brown noise', _noise, () {
                    setState(() => _noise = !_noise);
                    _noise ? Native.startNoise() : Native.stopNoise();
                  }, onColor: C.leaf, dark: true),
                  if (cfg.camera) Sel('🌑 Stealth dim', false, () => setState(() => _dim = true), dark: true),
                  Sel(cfg.strict ? '🔒 End early (PIN)' : 'End early', false, _endEarly, dark: true),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          if (_dim)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _dim = false),
                child: Container(
                  color: Colors.black, alignment: Alignment.bottomCenter,
                  padding: const EdgeInsets.only(bottom: 40),
                  child: const Text('tap to wake', style: TextStyle(color: Color(0xFF222222), fontSize: 12)),
                ),
              ),
            ),
        ]),
      ),
    );
  }
}
