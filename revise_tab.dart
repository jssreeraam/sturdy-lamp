import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'models.dart';
import 'store.dart';
import 'theme.dart';
import 'widgets.dart';

class ReviseTab extends ConsumerWidget {
  const ReviseTab({super.key});

  Future<void> _addPearl(BuildContext context, AppStore st) async {
    final t = TextEditingController();
    String subj = 'General';
    bool hy = false;
    await showDialog(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (ctx, set) => AlertDialog(
          backgroundColor: C.cream,
          title: const Text('Add Pearl'),
          content: SingleChildScrollView(
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              TextField(controller: t, maxLength: 120, maxLines: 2, decoration: const InputDecoration(hintText: 'Ward / clinical pearl', counterText: '')),
              const SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: subj,
                items: [for (final s in subjectsAll) DropdownMenuItem(value: s, child: Text(s))],
                onChanged: (v) => set(() => subj = v ?? 'General'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero, activeColor: C.tangerine,
                title: const Text('High-Yield ★'), value: hy, onChanged: (v) => set(() => hy = v),
              ),
            ]),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            TextButton(
              onPressed: () async {
                if (t.text.trim().isNotEmpty) await st.addRevision(t.text.trim(), subj, hy);
                if (ctx.mounted) Navigator.pop(ctx);
              },
              child: const Text('Add'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _card(AppStore st, Revision r, {bool due = false}) {
    final today = st.todayNum;
    final overdue = due && r.due! < today;
    return Bento(
      color: C.lavender,
      margin: const EdgeInsets.only(bottom: 10),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          if (r.highYield) const Text('★ ', style: TextStyle(color: C.tangerine, fontSize: 18, fontWeight: FontWeight.w900)),
          Expanded(child: Text(r.topic, style: hs(16))),
        ]),
        const SizedBox(height: 4),
        Text(
          '${r.subject} · Rev ${r.stage + 1}/${stageDays.length}'
          '${r.mastered ? '' : overdue ? ' · overdue ${today - r.due!}d' : due ? ' · due today' : ' · due ${fmtDay(r.due!)}'}',
          style: cap(color: overdue ? C.crimson : C.muted, w: FontWeight.w700),
        ),
        if (due) ...[
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: InkBtn('Ticked Done +30 XP', onTap: () => st.markDone(r), bg: C.leaf)),
            const SizedBox(width: 8),
            InkBtn('Forgot', onTap: () => st.markForgot(r), bg: C.crimson),
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final st = ref.watch(storeProvider);
    final today = st.todayNum;
    final active = st.revs.where((r) => !r.mastered).toList();
    final dueList = active.where((r) => r.due! <= today).toList()
      ..sort((a, b) {
        if (a.highYield != b.highYield) return a.highYield ? -1 : 1;
        return a.due!.compareTo(b.due!);
      });
    final upcoming = active.where((r) => r.due! > today).toList()..sort((a, b) => a.due!.compareTo(b.due!));
    final mastered = st.revs.where((r) => r.mastered).toList();

    return ListView(padding: const EdgeInsets.fromLTRB(16, 14, 16, 24), children: [
      Row(children: [
        Expanded(child: Text('Revise', style: hs(28))),
        InkBtn('+ Add Pearl', onTap: () => _addPearl(context, st), bg: C.tangerine),
      ]),
      const SizedBox(height: 14),
      if (dueList.isEmpty)
        Bento(
          color: C.sage,
          child: Column(children: [
            const Text('🎉', style: TextStyle(fontSize: 40)),
            const SizedBox(height: 6),
            Text('All Revisions Cleared', style: hs(20)),
            Text('Nothing due today. Log a study block to feed the queue.', textAlign: TextAlign.center, style: cap(color: C.ink)),
          ]),
        )
      else ...[
        SectionTitle('Due Today & Overdue', sub: '${dueList.length} topics · High-Yield ★ pinned first'),
        for (final r in dueList) _card(st, r, due: true),
      ],
      if (upcoming.isNotEmpty) ...[
        const SizedBox(height: 10),
        const SectionTitle('Upcoming'),
        for (final r in upcoming.take(12)) _card(st, r),
        if (upcoming.length > 12) Text('+ ${upcoming.length - 12} more scheduled', style: cap()),
      ],
      if (mastered.isNotEmpty) ...[
        const SizedBox(height: 14),
        Bento(
          color: C.butter,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Mastered Vault 🏆 (${mastered.length})', style: hs(17)),
              children: [
                for (final r in mastered)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(r.topic, style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(r.subject),
                    trailing: IconButton(icon: const Icon(Icons.delete_outline), onPressed: () => st.deleteRevision(r)),
                  ),
              ],
            ),
          ),
        ),
      ],
    ]);
  }
}
