const subjects19 = [
  'Medicine', 'Surgery', 'OBG', 'Pediatrics', 'PSM', 'Pathology', 'Pharmacology',
  'Microbiology', 'Anatomy', 'Physiology', 'Biochemistry', 'FMT', 'ENT',
  'Ophthalmology', 'Orthopedics', 'Anesthesia', 'Radiology', 'Dermatology', 'Psychiatry',
];
const subjectsAll = [...subjects19, 'General'];
const studyModes = ['Reading', 'QBank', 'Revision', 'Grand Test'];
const durations = [15, 25, 50, 90, 120, 180];
const stageDays = [1, 3, 7, 21, 45];
const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

String durLabel(int m) => m == 180 ? '180m Hardcore GT' : '${m}m';

int dayNum(DateTime d) =>
    DateTime.utc(d.year, d.month, d.day).millisecondsSinceEpoch ~/ 86400000;
DateTime dayDate(int n) => DateTime.fromMillisecondsSinceEpoch(n * 86400000, isUtc: true);
String fmtDay(int n) {
  final d = dayDate(n);
  return '${d.day} ${months[d.month - 1]}';
}

String hm(double minutes) {
  final m = minutes.round();
  if (m < 60) return '${m}m';
  return '${m ~/ 60}h ${(m % 60).toString().padLeft(2, '0')}m';
}

String mmss(int secs) {
  if (secs < 0) secs = 0;
  final h = secs ~/ 3600, m = (secs % 3600) ~/ 60, s = secs % 60;
  final mm = m.toString().padLeft(2, '0'), ss = s.toString().padLeft(2, '0');
  return h > 0 ? '$h:$mm:$ss' : '$mm:$ss';
}

class SessionConfig {
  final String subject, mode, goal;
  final int minutes, intervalSec;
  final bool camera, front;
  const SessionConfig({
    required this.subject, required this.mode, required this.goal,
    required this.minutes, required this.camera, required this.front,
    required this.intervalSec,
  });
  bool get hardcore => minutes >= 180;
}

class SessionResult {
  final SessionConfig cfg;
  final DateTime start;
  final int durationSec, focus, tokens;
  final bool failed;
  const SessionResult({
    required this.cfg, required this.start, required this.durationSec,
    required this.focus, required this.tokens, required this.failed,
  });
}

class Session {
  int? id;
  int startMs, durationSec, plannedMin, focus, tokens, mcqTotal, mcqCorrect, xp;
  String subject, mode, kind, goal;
  bool failed, highYield, hardcore;
  int? gt;

  Session({
    this.id, required this.startMs, required this.durationSec, required this.plannedMin,
    required this.subject, required this.mode, required this.kind, required this.goal,
    required this.focus, required this.tokens, required this.failed,
    this.mcqTotal = 0, this.mcqCorrect = 0, this.gt, this.highYield = false,
    required this.xp, this.hardcore = false,
  });

  double get minutes => durationSec / 60.0;
  int get endMs => startMs + durationSec * 1000;

  Map<String, Object?> toMap() => {
        'id': id, 'startMs': startMs, 'durationSec': durationSec, 'plannedMin': plannedMin,
        'subject': subject, 'mode': mode, 'kind': kind, 'goal': goal, 'focus': focus,
        'tokens': tokens, 'failed': failed ? 1 : 0, 'mcqTotal': mcqTotal,
        'mcqCorrect': mcqCorrect, 'gt': gt, 'highYield': highYield ? 1 : 0, 'xp': xp,
        'hardcore': hardcore ? 1 : 0,
      };

  factory Session.fromMap(Map<String, Object?> m) => Session(
        id: m['id'] as int?,
        startMs: m['startMs'] as int,
        durationSec: m['durationSec'] as int,
        plannedMin: m['plannedMin'] as int,
        subject: m['subject'] as String,
        mode: m['mode'] as String,
        kind: m['kind'] as String,
        goal: (m['goal'] as String?) ?? '',
        focus: m['focus'] as int,
        tokens: m['tokens'] as int,
        failed: (m['failed'] as int) == 1,
        mcqTotal: (m['mcqTotal'] as int?) ?? 0,
        mcqCorrect: (m['mcqCorrect'] as int?) ?? 0,
        gt: m['gt'] as int?,
        highYield: (m['highYield'] as int?) == 1,
        xp: (m['xp'] as int?) ?? 0,
        hardcore: (m['hardcore'] as int?) == 1,
      );
}

class Revision {
  int? id;
  String topic, subject;
  bool highYield, mastered;
  int stage, baseDay;

  Revision({
    this.id, required this.topic, required this.subject, required this.highYield,
    required this.stage, required this.baseDay, required this.mastered,
  });

  int? get due => mastered ? null : baseDay + stageDays[stage];

  Map<String, Object?> toMap() => {
        'id': id, 'topic': topic, 'subject': subject, 'highYield': highYield ? 1 : 0,
        'stage': stage, 'baseDay': baseDay, 'mastered': mastered ? 1 : 0,
      };

  factory Revision.fromMap(Map<String, Object?> m) => Revision(
        id: m['id'] as int?,
        topic: m['topic'] as String,
        subject: (m['subject'] as String?) ?? 'General',
        highYield: (m['highYield'] as int?) == 1,
        stage: m['stage'] as int,
        baseDay: m['baseDay'] as int,
        mastered: (m['mastered'] as int?) == 1,
      );
}

class Achv {
  final String emoji, title, hint;
  final bool earned;
  const Achv(this.emoji, this.title, this.hint, this.earned);
}
