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
  int tokens = 5, nStudy = 0, nNeutral = 0, nDist = 0, nAbs = 0;
  bool _prevBad = false, _busy = false, _dim = false, _noise = false, _done = false, _ready = false;
  String _status = 'Preparing…';

  SessionConfig get cfg => widget.cfg;
  int get total => cfg.minutes * 60;

  @override
  void initState() {
    super.initState();
    _begin();
  }

  Future<void> _begin() async {
    final st = ref.read(storeProvider);
    Native.keepScreenOn(true);
    Native.scheduleSessionAlert(total * 1000);
    if (cfg.camera) {
      final ok = await _initCam();
      if (!ok) return;
    } else {
      await Native.startLock(total * 1000, st.apps, st.nuclear);
      _status = 'Locked in. Go study.';
    }
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
      final c = CameraController(cam, ResolutionPreset.medium, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(FlashMode.off);
      _cam = c;
      _face = FaceDetector(options: FaceDetectorOptions(enableClassification: true, performanceMode: FaceDetectorMode.fast));
      _lab = ImageLabeler(options: ImageLabelerOptions(confidenceThreshold: 0.55));
      _status = 'Watching quietly…';
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
                ));
        _cleanup(clearLock: false);
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
      _classify(faces, labels.map((l) => l.label.toLowerCase()).toList());
    } catch (_) {
    } finally {
      if (f != null) { try { await File(f.path).delete(); } catch (_) {} }
      _busy = false;
    }
  }

  bool _has(List<String> names, List<String> keys) => names.any((n) => keys.any((k) => n.contains(k)));

  void _classify(List<Face> faces, List<String> names) {
    final props = _has(names, ['book', 'paper', 'text', 'notebook', 'pen', 'document', 'publication', 'laptop', 'tablet', 'writing', 'stationery', 'desk']);
    final phone = _has(names, ['mobile phone', 'smartphone', 'telephone']);
    final person = _has(names, ['person', 'human', 'hand', 'finger', 'arm', 'skin', 'shoulder', 'sleeve']);
    String kind;
    if (faces.isEmpty) {
      kind = person ? 'Neutral' : 'Absent';
    } else {
      final sorted = [...faces];
      sorted.sort((a, b) => (b.boundingBox.width * b.boundingBox.height).compareTo(a.boundingBox.width * a.boundingBox.height));
      final fc = sorted.first;
      final l = fc.leftEyeOpenProbability ?? 1, r = fc.rightEyeOpenProbability ?? 1;
      final yaw = (fc.headEulerAngleY ?? 0).abs();
      final pitch = fc.headEulerAngleX ?? 0;
      if (l < 0.2 && r < 0.2 && pitch > -8) {
        kind = 'Distracted';
      } else if (yaw > 40 || phone) {
        kind = 'Distracted';
      } else if (props || pitch < -8) {
        kind = 'Study';
      } else {
        kind = 'Neutral';
      }
    }
    final bad = kind == 'Distracted' || kind == 'Absent';
    if (bad && _prevBad) {
      // two consecutive hits required, so writing notes never causes false penalties
      if (kind == 'Absent') {
        nAbs++; tokens -= 2; Native.vibrate([0, 450]);
      } else {
        nDist++; tokens -= 1; Native.vibrate([0, 120, 90, 120]);
      }
      _status = kind == 'Absent' ? 'You left the desk. -2 tokens' : 'Drifting. -1 token';
    } else if (bad) {
      nNeutral++;
      _status = 'Checking in…';
    } else if (kind == 'Study') {
      nStudy++; _status = 'Deep focus ✓';
    } else {
      nNeutral++; _status = 'Steady';
    }
    _prevBad = bad;
    if (mounted) setState(() {});
    if (tokens <= 0) _finish(failed: true);
  }

  int get _focus {
    final t = nStudy + nNeutral + nDist + nAbs;
    return t == 0 ? 100 : (((nStudy + nNeutral) * 100) / t).round();
  }

  void _cleanup({bool clearLock = true}) {
    _tick?.cancel(); _shot?.cancel();
    _cam?.dispose(); _face?.close(); _lab?.close();
    _cam = null; _face = null; _lab = null;
    Native.keepScreenOn(false);
    Native.stopNoise();
    Native.cancelSessionAlert();
    if (clearLock && !cfg.camera) Native.clearLock();
  }

  Future<void> _finish({bool failed = false, bool abandoned = false}) async {
    if (_done) return;
    _done = true;
    final int secs = _ready ? DateTime.now().difference(_start).inSeconds.clamp(0, total).toInt() : 0;
    _cleanup();
    final penalise = abandoned && cfg.hardcore;
    if (penalise) {
      final st = ref.read(storeProvider);
      await Native.startLock(2 * 3600 * 1000, st.apps, true); // full lockdown for quitting a Hardcore GT
    }
    if (!mounted) return;
    if (abandoned && secs < 60) { Navigator.pop(context, null); return; }
    Navigator.pop(
        context,
        SessionResult(cfg: cfg, start: _start, durationSec: secs, focus: cfg.camera ? _focus : 100,
            tokens: tokens.clamp(0, 5).toInt(), failed: failed || penalise));
  }

  Future<void> _abandon() async {
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
                    Text('❤️' * tokens.clamp(0, 5).toInt() + '🖤' * (5 - tokens.clamp(0, 5).toInt()), style: const TextStyle(fontSize: 16)),
                ]),
                const Spacer(),
                StudyGirl(progress: total == 0 ? 0 : _elapsed / total, running: _ready, size: 300),
                const SizedBox(height: 10),
                Text(mmss(remaining), style: hs(54, color: Colors.white)),
                const SizedBox(height: 6),
                Text(_status, style: cap(color: Colors.white60, size: 14)),
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
                  Sel('End early', false, _abandon, dark: true),
                ]),
                const SizedBox(height: 8),
              ]),
            ),
          ),
          if (_dim)
            Positioned.fill(
              child: GestureDetector(
                onTap: () => setState(() => _dim = false),
                child: Container(color: Colors.black, alignment: Alignment.bottomCenter,
                    padding: const EdgeInsets.only(bottom: 40),
                    child: const Text('tap to wake', style: TextStyle(color: Color(0xFF222222), fontSize: 12))),
              ),
            ),
        ]),
      ),
    );
  }
}
