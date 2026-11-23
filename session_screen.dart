import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';
import 'models.dart';
import 'native.dart';
import 'store.dart';
import 'girl.dart';
import 'theme.dart';
import 'widgets.dart';

class SessionScreen extends ConsumerStatefulWidget {
  final SessionConfig cfg;
  const SessionScreen({super.key, required this.cfg});
  @override
  ConsumerState<SessionScreen> createState() => _SessionScreenState();
}

class _SessionScreenState extends ConsumerState<SessionScreen> {
  DateTime _start = DateTime.now();
  Timer? _tick, _shot;
  int _elapsed = 0;
  CameraController? _cam;
  FaceDetector? _face;
  ImageLabeler? _lab;

  late final bool calibrating;
  late final int maxLives;
  int tokens = 0, nStudy = 0, nNeutral = 0, nBad = 0, distractions = 0, points = 0;
  bool _prevBad = false, _busy = false, _dim = false, _noise = false;
  bool _done = false, _ready = false, _locked = false;
  String _status = 'Preparing…';
  final List<List<double>> _hist = []; // recent face metrics for the live-face check

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
      final cams = await availableCameras();
      final dir = cfg.front ? CameraLensDirection.front : CameraLensDirection.back;
      final cam = cams.firstWhere((c) => c.lensDirection == dir, orElse: () => cams.first);
      final c = CameraController(cam, ResolutionPreset.high, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      _cam = c;
      _face = FaceDetector(
        options: FaceDetectorOptions(
          enableClassification: true,
          performanceMode: FaceDetectorMode.accurate,
          minFaceSize: 0.08,
        ),
      );
      _lab = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.4));
      _status = calibrating ? 'Calibration day: learning your focus pattern…' : 'Watching quietly…';
      _shot = Timer.periodic(Duration(seconds: cfg.intervalSec), (_) => _capture());
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

  Future<void> _capture() async {
    if (_busy || _done || _cam == null || !_cam!.value.isInitialized) return;
    _busy = true;
    XFile? f;
    try {
      await _cam!.setFlashMode(FlashMode.off); // flash is NEVER allowed to fire
      f = await _cam!.takePicture();
      final img = InputImage.fromFilePath(f.path);
      final faces = await _face!.processImage(img);
      final labels = await _lab!.processImage(img);
      _classify(faces, labels);
    } catch (_) {
    } finally {
      if (f != null) { try { await File(f.path).delete(); } catch (_) {} }
      _busy = false;
    }
  }

  /// A photo / frozen video of a face never changes. A live face always jitters a little.
  bool _isStatic(Face f) {
    final b = f.boundingBox;
    _hist.add([
      b.left, b.top, b.width, b.height,
      f.headEulerAngleY ?? 0, f.headEulerAngleX ?? 0,
      f.leftEyeOpenProbability ?? 0, f.rightEyeOpenProbability ?? 0,
    ]);
    if (_hist.length > 3) _hist.removeAt(0);
    if (_hist.length < 3) return false;
    for (int i = 1; i < 3; i++) {
      for (int k = 0; k < 4; k++) { if ((_hist[i][k] - _hist[0][k]).abs() > 4) return false; }
      if ((_hist[i][4] - _hist[0][4]).abs() > 0.4 || (_hist[i][5] - _hist[0][5]).abs() > 0.4) return false;
      if ((_hist[i][6] - _hist[0][6]).abs() > 0.03 || (_hist[i][7] - _hist[0][7]).abs() > 0.03) return false;
    }
    return true;
  }

  void _classify(List<Face> faces, List<ImageLabel> labels) {
    bool has(List<String> keys, double minC) =>
        labels.any((l) => l.confidence >= minC && keys.any((k) => l.label.toLowerCase().contains(k)));
    final bookish = has(['book', 'paper', 'notebook', 'text', 'writing', 'stationery', 'publication', 'document', 'handwriting', 'pen'], 0.4);
    final device = has(['mobile phone', 'smartphone', 'telephone', 'communication device', 'laptop', 'netbook', 'tablet', 'television', 'computer monitor', 'display device', 'screen', 'computer'], 0.65);
    final person = has(['person', 'human', 'hand', 'finger', 'arm', 'hair', 'head', 'forehead', 'skin', 'shoulder', 'sleeve', 'neck', 'chin', 'cheek'], 0.4);

    String kind;
    if (device) {
      kind = 'Device'; // using another device
    } else if (faces.isEmpty) {
      _hist.clear();
      // head tipped far down over a book can hide the face; a person + book is still studying
      kind = (bookish && person) ? 'Study' : 'Absent';
    } else {
      final sorted = [...faces];
      sorted.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      final fc = sorted.first;
      final l = fc.leftEyeOpenProbability, r = fc.rightEyeOpenProbability;
      final eyesClosed = l != null && r != null && l < 0.25 && r < 0.25;
      final yaw = (fc.headEulerAngleY ?? 0).abs();
      final pitch = fc.headEulerAngleX ?? 0; // negative = looking down
      final roll = (fc.headEulerAngleZ ?? 0).abs();
      if (_isStatic(fc)) {
        kind = 'Static';
      } else if (pitch < -8) {
        // looking down at the book: eyes are NOT considered at all
        kind = yaw > 60 ? 'Distracted' : 'Study';
      } else if (eyesClosed || roll > 40) {
        kind = 'Sleeping';
      } else if (yaw > 45) {
        kind = 'Distracted';
      } else {
        kind = bookish ? 'Study' : 'Neutral';
      }
    }

    const badKinds = {'Distracted', 'Absent', 'Device', 'Static', 'Sleeping'};
    final bad = badKinds.contains(kind);
    if (bad && _prevBad) {
      // two checks in a row required, so a quick glance never costs a life
      distractions++;
      nBad++;
      if (!calibrating) tokens--;
      Native.vibrate(kind == 'Absent' ? [0, 450] : [0, 120, 90, 120]);
      final why = {
        'Absent': 'Not in frame',
        'Device': 'Another device in view',
        'Sleeping': 'Looks asleep',
        'Static': 'Face is not live',
        'Distracted': 'Looking away',
      }[kind]!;
      _status = calibrating ? '$why (calibration: no life lost)' : '$why. -1 life';
    } else if (bad) {
      nNeutral++;
      _status = 'Checking in…';
    } else if (kind == 'Study') {
      nStudy++; points += 2; _status = 'Deep focus ✓ +2';
    } else {
      nNeutral++; points += 1; _status = 'Steady +1';
    }
    _prevBad = bad;
    if (mounted) setState(() {});
    if (!calibrating && cfg.camera && tokens <= 0) _finish(failed: true);
  }

  int get _focus {
    final t = nStudy + nNeutral + nBad;
    return t == 0 ? 100 : (((nStudy + nNeutral) * 100) / t).round();
  }

  void _cleanup() {
    _tick?.cancel();
    _shot?.cancel();
    _cam?.dispose();
    _face?.close();
    _lab?.close();
    _cam = null; _face = null; _lab = null;
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
