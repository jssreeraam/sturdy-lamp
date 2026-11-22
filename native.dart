import 'package:flutter/services.dart';

class AppInfo {
  final String pkg, label;
  AppInfo(this.pkg, this.label);
}

class LockStatus {
  final bool active, nuclear;
  final int remainingMs;
  final List<String> pkgs;
  const LockStatus(this.active, this.remainingMs, this.nuclear, this.pkgs);
  static const none = LockStatus(false, 0, false, []);
}

class Native {
  static const _ch = MethodChannel('focusguard/blocker');

  static Future<T?> _c<T>(String m, [dynamic a]) async {
    try {
      return await _ch.invokeMethod<T>(m, a);
    } catch (_) {
      return null;
    }
  }

  static Future<List<AppInfo>> apps() async {
    final r = await _c<List<dynamic>>('apps');
    if (r == null) return [];
    return r.map((e) {
      final m = Map<dynamic, dynamic>.from(e as Map);
      return AppInfo(m['pkg'] as String, m['label'] as String);
    }).toList();
  }

  static Future<void> startLock(int ms, List<String> pkgs, bool nuclear) =>
      _c('startLock', {'ms': ms, 'pkgs': pkgs, 'nuclear': nuclear});
  static Future<void> clearLock() => _c('clearLock');

  static Future<LockStatus> lockStatus() async {
    final r = await _c<Map<dynamic, dynamic>>('lockStatus');
    if (r == null) return LockStatus.none;
    return LockStatus(
      r['active'] == true,
      (r['remainingMs'] as num?)?.toInt() ?? 0,
      r['nuclear'] == true,
      ((r['pkgs'] as List?) ?? []).map((e) => e.toString()).toList(),
    );
  }

  static Future<bool> isA11yEnabled() async => (await _c<bool>('isA11yEnabled')) ?? false;
  static Future<void> openA11y() => _c('openA11y');
  static Future<bool> isAdminActive() async => (await _c<bool>('isAdminActive')) ?? false;
  static Future<void> requestAdmin() => _c('requestAdmin');
  static Future<bool> removeAdmin() async => (await _c<bool>('removeAdmin')) ?? false;
  static Future<void> keepScreenOn(bool on) => _c('keepScreenOn', {'on': on});
  static Future<void> startNoise() => _c('startNoise');
  static Future<void> stopNoise() => _c('stopNoise');
  static Future<void> vibrate(List<int> pattern) => _c('vibrate', {'p': pattern});
  static Future<void> requestNotif() => _c('requestNotif');
  static Future<void> setReminder(bool on, int h, int m) =>
      _c('setReminder', {'on': on, 'h': h, 'm': m});
  static Future<void> setDueCount(int n) => _c('setDueCount', {'n': n});
  static Future<void> scheduleSessionAlert(int ms) => _c('scheduleSessionAlert', {'ms': ms});
  static Future<void> cancelSessionAlert() => _c('cancelSessionAlert');
}
