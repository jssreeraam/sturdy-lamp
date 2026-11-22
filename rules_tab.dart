import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'native.dart';
import 'store.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

class RulesTab extends ConsumerStatefulWidget {
  const RulesTab({super.key});
  @override
  ConsumerState<RulesTab> createState() => _RulesTabState();
}

class _RulesTabState extends ConsumerState<RulesTab> with WidgetsBindingObserver {
  bool admin = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _admin();
  }
  @override
  void dispose() { WidgetsBinding.instance.removeObserver(this); super.dispose(); }
  @override
  void didChangeAppLifecycleState(AppLifecycleState s) { if (s == AppLifecycleState.resumed) _admin(); }
  Future<void> _admin() async {
    final a = await Native.isAdminActive();
    if (mounted) setState(() => admin = a);
  }

  void snack(String m) => ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(m)));

  Future<String?> _askPin(String title, {String? hint}) {
    final c = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.cream,
        title: Text(title),
        content: TextField(
          controller: c, autofocus: true, obscureText: true, maxLength: 6,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: hint ?? '6-digit PIN', counterText: ''),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, c.text), child: const Text('OK')),
        ],
      ),
    );
  }

  Future<void> _setPin(AppStore st, bool locked) async {
    if (locked) { snack('The PIN cannot be set or changed while a lock is active.'); return; }
    final a = await _askPin(st.hasPin ? 'New Guardian PIN' : 'Set Guardian PIN', hint: 'Give this to Mom/Dad');
    if (a == null) return;
    if (!RegExp(r'^\d{6}$').hasMatch(a)) { snack('PIN must be exactly 6 digits.'); return; }
    final b = await _askPin('Confirm PIN');
    if (b != a) { snack('PINs did not match.'); return; }
    await st.setPin(a);
    snack('Guardian PIN saved.');
  }

  Future<void> _emergency(AppStore st) async {
    if (!st.hasPin) { snack('No Guardian PIN set.'); return; }
    final p = await _askPin('Guardian emergency unlock');
    if (p == null) return;
    if (st.checkPin(p)) {
      await Native.clearLock();
      await st.bumpHonesty();
      snack('Lock cleared. Honesty counter +1.');
    } else {
      snack('Wrong PIN.');
    }
  }

  Future<void> _goals(AppStore st) async {
    final d = TextEditingController(text: st.dutyH.toString()), o = TextEditingController(text: st.offH.toString());
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: C.cream,
        title: const Text('Daily goals (hours)'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: d, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Duty Day')),
          const SizedBox(height: 10),
          TextField(controller: o, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Off Day')),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Save')),
        ],
      ),
    );
    if (ok == true) {
      final dv = double.tryParse(d.text), ov = double.tryParse(o.text);
      if (dv != null && ov != null && dv > 0 && ov > 0) await st.setGoals(dv, ov);
    }
  }

  Future<void> _time(AppStore st) async {
    final t = await showTimePicker(context: context, initialTime: TimeOfDay(hour: st.remH, minute: st.remM));
    if (t != null) await st.setReminder(true, t.hour, t.minute);
  }

  Future<void> _restore(AppStore st) async {
    final data = await Clipboard.getData('text/plain');
    final text = data?.text ?? '';
    if (!text.contains('"sessions"')) { snack('Clipboard has no FocusGuard backup.'); return; }
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore from clipboard?'),
        content: const Text('This REPLACES all current sessions and revisions.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Restore')),
        ],
      ),
    );
    if (ok != true) return;
    snack(await st.importJson(text) ? 'Backup restored.' : 'Backup was invalid.');
  }

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storeProvider);
    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Text('Rules', style: hs(28)),
      const SizedBox(height: 14),
      const _LockPanel(),
      const A11yWarn(),

      Bento(
        color: C.night,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Anti-Tamper Vault', style: hs(18, color: Colors.white)),
          const SizedBox(height: 4),
          Text('Locks use a monotonic clock, so changing Date & Time never clears them. While locked, the Settings screens for this app, accessibility, device admin, uninstall, force stop and date & time are closed on sight.',
              style: cap(color: Colors.white60)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('${st.apps.length} distraction apps', style: cap(color: Colors.white, w: FontWeight.w800, size: 14))),
            Sel('Pick apps', false, () async {
              final r = await showModalBottomSheet<List<String>>(
                  context: context, isScrollControlled: true, backgroundColor: C.cream,
                  builder: (_) => AppPicker(selected: st.apps));
              if (r != null) st.setApps(r);
            }, dark: true),
          ]),
          SwitchListTile(
            contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
            title: const Text('Nuclear mode', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text('Block ALL of Android Settings while locked', style: cap(color: Colors.white60)),
            value: st.nuclear, onChanged: st.setNuclear,
          ),
          SwitchListTile(
            contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
            title: const Text('Uninstall Guard', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
            subtitle: Text('Device admin greys out Uninstall (opt-in)', style: cap(color: Colors.white60)),
            value: admin,
            onChanged: (v) async {
              if (v) { await Native.requestAdmin(); }
              else {
                final ok = await Native.removeAdmin();
                if (!ok) snack('Cannot disable the Uninstall Guard while a lock is active.');
              }
              await _admin();
            },
          ),
        ]),
      ),

      FutureBuilder<LockStatus>(
        future: Native.lockStatus(),
        builder: (ctx, snap) {
          final locked = snap.data?.active ?? false;
          return Bento(
            color: C.peach,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Guardian PIN', style: hs(18)),
              Text('A 6-digit PIN held by Mom/Dad. Stored as a salted SHA-256 hash. It clears an active lock and adds to your honesty counter.', style: cap(color: C.ink)),
              const SizedBox(height: 10),
              Text('Honesty counter: ${st.honesty} emergency unlocks', style: cap(color: C.ink, w: FontWeight.w800, size: 14)),
              const SizedBox(height: 12),
              Wrap(spacing: 8, runSpacing: 8, children: [
                InkBtn(st.hasPin ? 'Change PIN' : 'Set PIN', onTap: () => _setPin(st, locked)),
                InkBtn('Emergency unlock', onTap: () => _emergency(st), bg: C.crimson),
              ]),
            ]),
          );
        },
      ),

      Bento(
        color: C.butter,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Goals & Reminders', style: hs(18)),
          const SizedBox(height: 8),
          Text('Duty ${st.dutyH}h · Off ${st.offH}h', style: cap(color: C.ink, size: 14, w: FontWeight.w700)),
          const SizedBox(height: 8),
          SwitchListTile(
            contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
            title: const Text('Daily revision reminder', style: TextStyle(fontWeight: FontWeight.w800)),
            subtitle: Text(TimeOfDay(hour: st.remH, minute: st.remM).format(context)),
            value: st.remindOn, onChanged: (v) => st.setReminder(v, st.remH, st.remM),
          ),
          Wrap(spacing: 8, children: [
            InkBtn('Edit goals', onTap: () => _goals(st)),
            InkBtn('Reminder time', onTap: () => _time(st), bg: C.tangerine),
          ]),
        ]),
      ),

      Bento(
        color: C.sky,
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Backup & Restore', style: hs(18)),
          Text('Everything lives on this phone only. Copy a backup, paste it in a note or chat to yourself.', style: cap(color: C.ink)),
          const SizedBox(height: 12),
          Wrap(spacing: 8, children: [
            InkBtn('Copy backup', onTap: () async {
              await Clipboard.setData(ClipboardData(text: st.exportJson()));
              snack('Backup copied (${st.sessions.length} sessions, ${st.revs.length} revisions).');
            }),
            InkBtn('Restore', onTap: () => _restore(st), bg: C.tangerine),
          ]),
        ]),
      ),
    ]);
  }
}

class _LockPanel extends StatelessWidget {
  const _LockPanel();
  @override
  Widget build(BuildContext context) => const LockBanner();
}
