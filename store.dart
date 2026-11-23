import 'dart:convert';
import 'dart:math';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as pth;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite/sqflite.dart';
import 'models.dart';
import 'native.dart';

final storeProvider = ChangeNotifierProvider<AppStore>((ref) => AppStore()..init());

class AppStore extends ChangeNotifier {
  late Database _db;
  late SharedPreferences sp;
  bool ready = false;
  List<Session> sessions = [];
  List<Revision> revs = [];

  Future<void> init() async {
    sp = await SharedPreferences.getInstance();
    final path = pth.join(await getDatabasesPath(), 'focusguard.db');
    _db = await openDatabase(path, version: 2, onUpgrade: (db, o, n) async {
      if (o < 2) { await db.execute('ALTER TABLE sessions ADD COLUMN distractions INTEGER DEFAULT 0'); }
    }, onCreate: (db, v) async {
      await db.execute(
          'CREATE TABLE sessions(id INTEGER PRIMARY KEY AUTOINCREMENT,startMs INTEGER,durationSec INTEGER,plannedMin INTEGER,subject TEXT,mode TEXT,kind TEXT,goal TEXT,focus INTEGER,tokens INTEGER,failed INTEGER,mcqTotal INTEGER,mcqCorrect INTEGER,gt INTEGER,highYield INTEGER,xp INTEGER,hardcore INTEGER,distractions INTEGER DEFAULT 0)');
      await db.execute(
          'CREATE TABLE revisions(id INTEGER PRIMARY KEY AUTOINCREMENT,topic TEXT,subject TEXT,highYield INTEGER,stage INTEGER,baseDay INTEGER,mastered INTEGER)');
    });
    await reload();
    ready = true;
    notifyListeners();
    final h = sp.getInt('remH') ?? 9, m = sp.getInt('remM') ?? 0;
    Native.requestNotif();
    Native.setReminder(remindOn, h, m);
  }

  Future<void> reload() async {
    sessions = (await _db.query('sessions', orderBy: 'startMs ASC')).map(Session.fromMap).toList();
    revs = (await _db.query('revisions')).map(Revision.fromMap).toList();
    notifyListeners();
    Native.setDueCount(dueCount);
  }

  // ---------- prefs ----------
  bool get duty => sp.getBool('duty') ?? true;
  double get dutyH => sp.getDouble('dutyH') ?? 2;
  double get offH => sp.getDouble('offH') ?? 7;
  double get goalH => duty ? dutyH : offH;
  int get revXp => sp.getInt('revXp') ?? 0;
  bool get strict => sp.getBool('strict') ?? false;
  bool get nuclear => sp.getBool('nuclear') ?? false;
  List<String> get apps => sp.getStringList('apps') ?? [];
  List<String> get allowedApps => sp.getStringList('allowed') ?? [];
  bool get front => sp.getBool('front') ?? false;
  int get interval => sp.getInt('interval') ?? 30;
  int get honesty => sp.getInt('honesty') ?? 0;
  bool get remindOn => sp.getBool('remOn') ?? true;
  int get remH => sp.getInt('remH') ?? 9;
  int get remM => sp.getInt('remM') ?? 0;
  bool get hasPin => sp.getString('pinHash') != null;

  DateTime get iniCet => DateTime.fromMillisecondsSinceEpoch(
      sp.getInt('ini') ?? DateTime(2027, 5, 1).millisecondsSinceEpoch);
  DateTime get neetPg => DateTime.fromMillisecondsSinceEpoch(
      sp.getInt('neet') ?? DateTime(2027, 8, 15).millisecondsSinceEpoch);

  Future<void> _set(Future<bool> f) async { await f; notifyListeners(); }
  Future<void> setDuty(bool v) => _set(sp.setBool('duty', v));
  Future<void> setGoals(double d, double o) async {
    await sp.setDouble('dutyH', d); await sp.setDouble('offH', o); notifyListeners();
  }
  Future<void> setExam(bool ini, DateTime d) =>
      _set(sp.setInt(ini ? 'ini' : 'neet', d.millisecondsSinceEpoch));
  Future<void> setStrict(bool v) => _set(sp.setBool('strict', v));
  Future<void> setNuclear(bool v) => _set(sp.setBool('nuclear', v));
  Future<void> setApps(List<String> a) => _set(sp.setStringList('apps', a));
  Future<void> setAllowedApps(List<String> a) => _set(sp.setStringList('allowed', a));
  Future<void> setFront(bool v) => _set(sp.setBool('front', v));
  Future<void> setInterval(int s) => _set(sp.setInt('interval', s));
  Future<void> bumpHonesty() => _set(sp.setInt('honesty', honesty + 1));
  Future<void> setReminder(bool on, int h, int m) async {
    await sp.setBool('remOn', on); await sp.setInt('remH', h); await sp.setInt('remM', m);
    await Native.setReminder(on, h, m);
    notifyListeners();
  }

  // ---------- guardian pin ----------
  String _h(String salt, String pin) => sha256.convert(utf8.encode('$salt:$pin')).toString();
  Future<void> setPin(String pin) async {
    final salt = base64Url.encode(List<int>.generate(16, (_) => Random.secure().nextInt(256)));
    await sp.setString('pinSalt', salt);
    await sp.setString('pinHash', _h(salt, pin));
    notifyListeners();
  }
  bool checkPin(String pin) =>
      hasPin && _h(sp.getString('pinSalt') ?? '', pin) == sp.getString('pinHash');

  // ---------- writes ----------
  Future<void> addSession(Session s) async {
    await _db.insert('sessions', s.toMap()..remove('id'));
    await reload();
  }

  Future<void> addRevision(String topic, String subject, bool hy) async {
    final r = Revision(topic: topic, subject: subject, highYield: hy, stage: 0,
        baseDay: todayNum, mastered: false);
    await _db.insert('revisions', r.toMap()..remove('id'));
    await reload();
  }

  Future<void> markDone(Revision r) async {
    r.stage++;
    if (r.stage >= stageDays.length) { r.stage = stageDays.length - 1; r.mastered = true; }
    await _db.update('revisions', r.toMap(), where: 'id=?', whereArgs: [r.id]);
    await sp.setInt('revXp', revXp + 30);
    await reload();
  }

  Future<void> markForgot(Revision r) async {
    r.stage = 0; r.baseDay = todayNum; r.mastered = false;
    await _db.update('revisions', r.toMap(), where: 'id=?', whereArgs: [r.id]);
    await reload();
  }

  Future<void> deleteRevision(Revision r) async {
    await _db.delete('revisions', where: 'id=?', whereArgs: [r.id]);
    await reload();
  }

  // ---------- backup ----------
  String exportJson() => jsonEncode({
        'v': 1,
        'revXp': revXp,
        'sessions': sessions.map((s) => s.toMap()).toList(),
        'revisions': revs.map((r) => r.toMap()).toList(),
      });

  Future<bool> importJson(String text) async {
    try {
      final m = jsonDecode(text) as Map<String, dynamic>;
      final ss = (m['sessions'] as List).map((e) => Session.fromMap(Map<String, Object?>.from(e as Map))).toList();
      final rs = (m['revisions'] as List).map((e) => Revision.fromMap(Map<String, Object?>.from(e as Map))).toList();
      await _db.transaction((t) async {
        await t.delete('sessions');
        await t.delete('revisions');
        for (final s in ss) { await t.insert('sessions', s.toMap()); }
        for (final r in rs) { await t.insert('revisions', r.toMap()); }
      });
      await sp.setInt('revXp', (m['revXp'] as num?)?.toInt() ?? 0);
      await reload();
      return true;
    } catch (_) {
      return false;
    }
  }

  // ---------- derived ----------
  int get todayNum => dayNum(DateTime.now());
  int _dayOf(Session s) => dayNum(DateTime.fromMillisecondsSinceEpoch(s.startMs));

  double minutesOn(int day) {
    double m = 0;
    for (final s in sessions) { if (_dayOf(s) == day) m += s.minutes; }
    return m;
  }
  double get todayMin => minutesOn(todayNum);

  int get dueCount => revs.where((r) => !r.mastered && r.due! <= todayNum).length;

  List<double> hourMinutesOn(int day) {
    final out = List<double>.filled(24, 0);
    final dayStart = DateTime.fromMillisecondsSinceEpoch(0, isUtc: true)
        .add(Duration(days: day));
    final local0 = DateTime(dayStart.year, dayStart.month, dayStart.day).millisecondsSinceEpoch;
    for (final s in sessions) {
      for (int h = 0; h < 24; h++) {
        final a = local0 + h * 3600000, b = a + 3600000;
        final o = min(b, s.endMs) - max(a, s.startMs);
        if (o > 0) out[h] += o / 60000.0;
      }
    }
    return out;
  }

  ({int streak, int shields}) streakInfo() {
    if (sessions.isEmpty) return (streak: 0, shields: 0);
    final byDay = <int, double>{};
    for (final s in sessions) { byDay[_dayOf(s)] = (byDay[_dayOf(s)] ?? 0) + s.minutes; }
    final first = byDay.keys.reduce(min);
    int run = 0, sh = 0;
    for (int d = first; d <= todayNum; d++) {
      final active = (byDay[d] ?? 0) >= 30;
      if (active) {
        run++;
        if (run % 7 == 0) sh = min(2, sh + 1);
      } else if (d == todayNum) {
        // today still in progress
      } else if (sh > 0) {
        sh--;
      } else {
        run = 0;
      }
    }
    return (streak: run, shields: sh);
  }

  int get totalXp => sessions.fold<int>(0, (a, s) => a + s.xp) + revXp;

  static const tiers = [
    ('Intern Warden', 0), ('Resident', 500), ('Chief Resident', 2000),
    ('AIIMS Ranker', 6000), ('AIR 1 Contender', 15000),
  ];
  int get tierIndex {
    int t = 0;
    for (int i = 0; i < tiers.length; i++) { if (totalXp >= tiers[i].$2) t = i; }
    return t;
  }
  String get rank => tiers[tierIndex].$1;
  double get tierProgress {
    final i = tierIndex;
    if (i >= tiers.length - 1) return 1;
    final a = tiers[i].$2, b = tiers[i + 1].$2;
    return ((totalXp - a) / (b - a)).clamp(0.0, 1.0).toDouble();
  }

  double monthProgress({double extraMin = 0}) {
    final now = DateTime.now();
    final dim = DateTime(now.year, now.month + 1, 0).day;
    final target = dim * ((dutyH + offH) / 2) * 60 * 0.8;
    final startMs = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    double m = extraMin;
    for (final s in sessions) { if (s.startMs >= startMs) m += s.minutes; }
    return (m / target).clamp(0.0, 1.0).toDouble();
  }

  int get cracks {
    final now = DateTime.now();
    final startMs = DateTime(now.year, now.month, 1).millisecondsSinceEpoch;
    int c = 0;
    for (final s in sessions.where((s) => s.startMs >= startMs)) {
      if (s.failed) { c++; } else if (s.focus >= 90 && c > 0) { c--; }
    }
    return min(c, 4);
  }

  Map<String, double> subjectMinutes(int days) {
    final out = <String, double>{};
    final from = todayNum - days + 1;
    for (final s in sessions) {
      if (_dayOf(s) >= from) out[s.subject] = (out[s.subject] ?? 0) + s.minutes;
    }
    return out;
  }

  /// days since subject last studied; null = never
  int? daysSince(String subject) {
    int? last;
    for (final s in sessions) {
      if (s.subject == subject) { final d = _dayOf(s); if (last == null || d > last) last = d; }
    }
    return last == null ? null : todayNum - last;
  }

  /// per-hour [minutes, focus-weighted minutes] over the last 30 days
  (List<double>, List<double>) hourFocus() {
    final mins = List<double>.filled(24, 0), w = List<double>.filled(24, 0);
    for (final s in sessions.where((s) => _dayOf(s) > todayNum - 30)) {
      for (int t = s.startMs; t < s.endMs; t += 60000) {
        final h = DateTime.fromMillisecondsSinceEpoch(t).hour;
        mins[h] += 1; w[h] += s.focus / 100.0;
      }
    }
    return (mins, w);
  }

  List<Achv> get badges {
    final hours = sessions.fold<double>(0, (a, s) => a + s.minutes) / 60;
    final mcq = sessions.fold<int>(0, (a, s) => a + s.mcqTotal);
    final mastered = revs.where((r) => r.mastered).length;
    final best = streakInfo().streak;
    return [
      Achv('🌱', 'First Block', 'Finish 1 session', sessions.isNotEmpty),
      Achv('🔥', '7-Day Streak', 'Study 30m+ for 7 days', best >= 7),
      Achv('⏱️', '50 Hour Club', 'Log 50 study hours', hours >= 50),
      Achv('🛡️', 'Iron Mind', 'Complete a 180m Hardcore GT',
          sessions.any((s) => s.hardcore && !s.failed && s.durationSec >= 170 * 60)),
      Achv('🧠', 'Memory Palace', 'Master 10 topics', mastered >= 10),
      Achv('🎯', 'MCQ Centurion', 'Solve 500 MCQs', mcq >= 500),
    ];
  }

  // ---------- lives (Day-1 calibration) ----------
  /// Day of the very first camera session = calibration day.
  int? get calDay {
    int? d;
    for (final s in sessions) {
      if (s.kind == 'camera') { final x = _dayOf(s); if (d == null || x < d) d = x; }
    }
    return d;
  }
  bool get calibrating { final d = calDay; return d == null || d == todayNum; }

  ({int dist, double hours}) get baseline {
    final d = calDay;
    if (d == null) return (dist: 0, hours: 0.0);
    int dist = 0; double sec = 0;
    for (final s in sessions) {
      if (s.kind == 'camera' && _dayOf(s) == d) { dist += s.distractions; sec += s.durationSec; }
    }
    return (dist: dist, hours: sec / 3600);
  }

  /// Lives for a camera block = 50% of the distractions you had on Day 1 in a block of the same length.
  int livesFor(int minutes) {
    if (calibrating) return 0;
    final b = baseline;
    if (b.hours < 0.5) return 5;
    final raw = 0.5 * (b.dist / b.hours) * (minutes / 60);
    return max(2, raw.ceil());
  }

  Future<void> forceRefresh() async { await reload(); }
}
