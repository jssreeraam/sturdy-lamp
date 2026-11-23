import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_image_labeling/google_mlkit_image_labeling.dart';

enum FocusState { study, neutral, distraction, absent, sleeping }

/// 100% on-device proctor.
/// Live face in frame = studying. Looking down at a book is NEVER penalised (eyes are ignored
/// unless the head is level AND closed for several checks in a row = asleep).
/// Absent = no face on 2 checks in a row. Another phone/tablet/laptop in view = distraction.
/// Any camera/ML error is treated as neutral, so a glitch never costs a life.
class VisionService {
  CameraController? cam;

  final FaceDetector _face = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true, // only used for the conservative "asleep" rule
      performanceMode: FaceDetectorMode.accurate,
      minFaceSize: 0.08,
    ),
  );
  final ImageLabeler _labels = ImageLabeler(
    options: ImageLabelerOptions(confidenceThreshold: .75),
  );

  int _miss = 0, _away = 0, _closed = 0;
  bool _capturing = false, _initializing = false;
  String lastInfo = 'Waiting for first check…';

  Future<void> init({bool front = false}) async {
    if (_initializing) return;
    _initializing = true;
    try {
      await _disposeCamera();
      final cams = await availableCameras();
      if (cams.isEmpty) throw StateError('No camera found on this device.');
      final want = front ? CameraLensDirection.front : CameraLensDirection.back;
      final selected = cams.firstWhere((c) => c.lensDirection == want, orElse: () => cams.first);
      final controller = CameraController(
        selected,
        ResolutionPreset.medium, // small faces stay detectable; still light on battery
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      try { await controller.setFlashMode(FlashMode.off); } catch (_) {}
      cam = controller;
      _miss = _away = _closed = 0;
      lastInfo = 'Camera ready (flash OFF)';
    } finally {
      _initializing = false;
    }
  }

  Future<FocusState> classify() async {
    final c = cam;
    if (c == null || !c.value.isInitialized || _capturing || _initializing) {
      lastInfo = 'Camera busy';
      return FocusState.neutral;
    }
    if (c.value.isTakingPicture) return FocusState.neutral;

    _capturing = true;
    XFile? shot;
    try {
      try { await c.setFlashMode(FlashMode.off); } catch (_) {} // flash must NEVER fire
      shot = await c.takePicture().timeout(const Duration(seconds: 8));
      final img = InputImage.fromFilePath(shot.path);
      final faces = await _face.processImage(img);

      if (faces.isEmpty) {
        _away = 0;
        _closed = 0;
        _miss++;
        lastInfo = _miss >= 2 ? 'Not in frame' : 'No face yet (grace)';
        return _miss >= 2 ? FocusState.absent : FocusState.neutral;
      }
      _miss = 0;

      // Isolated so a labeler error can never break face detection.
      try {
        final labels = await _labels.processImage(img);
        final device = labels.any((l) {
          final t = l.label.toLowerCase();
          return t.contains('phone') || t.contains('tablet') || t.contains('laptop') || t.contains('netbook');
        });
        if (device) {
          lastInfo = 'Another device in view';
          return FocusState.distraction;
        }
      } catch (_) {}

      final f = faces.reduce((a, b) =>
          (a.boundingBox.width * a.boundingBox.height) >= (b.boundingBox.width * b.boundingBox.height) ? a : b);
      final yaw = (f.headEulerAngleY ?? 0).abs();
      final pitch = f.headEulerAngleX ?? 0; // negative = looking down

      if (yaw > 50) {
        _away++;
        _closed = 0;
        lastInfo = 'Turned away (${yaw.round()}°)';
        return _away >= 2 ? FocusState.distraction : FocusState.neutral;
      }
      _away = 0;

      // Asleep = eyes shut while the head is level, 3 checks in a row. Looking down never counts.
      final l = f.leftEyeOpenProbability, r = f.rightEyeOpenProbability;
      final shut = l != null && r != null && l < 0.15 && r < 0.15 && pitch > -12;
      if (shut) {
        _closed++;
        lastInfo = 'Eyes closed ($_closed/3)';
        return _closed >= 3 ? FocusState.sleeping : FocusState.neutral;
      }
      _closed = 0;

      lastInfo = 'Live face locked in';
      return FocusState.study;
    } catch (e) {
      lastInfo = 'Check skipped';
      return FocusState.neutral;
    } finally {
      _capturing = false;
      if (shot != null) {
        try {
          final file = File(shot.path);
          if (await file.exists()) await file.delete();
        } catch (_) {}
      }
    }
  }

  Future<void> _disposeCamera() async {
    final c = cam;
    cam = null;
    if (c != null) { try { await c.dispose(); } catch (_) {} }
  }

  Future<void> dispose() async {
    await _disposeCamera();
    try { await _face.close(); } catch (_) {}
    try { await _labels.close(); } catch (_) {}
  }
}
