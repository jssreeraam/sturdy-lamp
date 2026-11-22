import 'dart:async';
import 'package:flutter/material.dart';
import 'native.dart';
import 'models.dart';
import 'theme.dart';

class Bento extends StatelessWidget {
  final Color color;
  final Widget child;
  final EdgeInsets padding, margin;
  final VoidCallback? onTap;
  const Bento({
    super.key, required this.color, required this.child,
    this.padding = const EdgeInsets.all(18),
    this.margin = const EdgeInsets.only(bottom: 14), this.onTap,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: margin,
        child: Material(
          color: color,
          borderRadius: BorderRadius.circular(24),
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

class InkBtn extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color bg, fg;
  final IconData? icon;
  final bool wide;
  const InkBtn(this.label, {super.key, this.onTap, this.bg = C.btn, this.fg = Colors.white,
      this.icon, this.wide = false});

  @override
  Widget build(BuildContext context) {
    final child = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 22, vertical: 15),
      child: Row(
        mainAxisSize: wide ? MainAxisSize.max : MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (icon != null) ...[Icon(icon, color: fg, size: 20), const SizedBox(width: 8)],
          Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w800, fontSize: 16)),
        ],
      ),
    );
    return Material(
      color: onTap == null ? Colors.black26 : bg,
      shape: const StadiumBorder(),
      child: InkWell(customBorder: const StadiumBorder(), onTap: onTap, child: child),
    );
  }
}

class Sel extends StatelessWidget {
  final String label;
  final bool on;
  final VoidCallback onTap;
  final Color onColor;
  final bool dark;
  const Sel(this.label, this.on, this.onTap,
      {super.key, this.onColor = C.btn, this.dark = false});

  @override
  Widget build(BuildContext context) {
    final fg = on ? Colors.white : (dark ? Colors.white70 : C.ink);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: on ? onColor : (dark ? Colors.white12 : Colors.white.withOpacity(0.65)),
          borderRadius: BorderRadius.circular(40),
        ),
        child: Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w700, fontSize: 13.5)),
      ),
    );
  }
}

class Bar extends StatelessWidget {
  final double value;
  final Color color, track;
  final double height;
  const Bar(this.value, {super.key, this.color = C.leaf, this.track = Colors.white54, this.height = 12});
  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: LinearProgressIndicator(
          value: value.clamp(0.0, 1.0).toDouble(), minHeight: height,
          backgroundColor: track, valueColor: AlwaysStoppedAnimation(color),
        ),
      );
}

class SectionTitle extends StatelessWidget {
  final String text;
  final String? sub;
  final Color color;
  const SectionTitle(this.text, {super.key, this.sub, this.color = C.ink});
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(text, style: hs(18, color: color)),
          if (sub != null) Text(sub!, style: cap(color: color.withOpacity(0.7))),
        ]),
      );
}

/// Shows a live countdown when a lock is active.
class LockBanner extends StatefulWidget {
  const LockBanner({super.key});
  @override
  State<LockBanner> createState() => _LockBannerState();
}

class _LockBannerState extends State<LockBanner> {
  Timer? _t;
  LockStatus st = LockStatus.none;
  @override
  void initState() {
    super.initState();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }
  Future<void> _poll() async {
    final s = await Native.lockStatus();
    if (mounted) setState(() => st = s);
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (!st.active) return const SizedBox.shrink();
    return Bento(
      color: C.night,
      child: Row(children: [
        const Text('🔒', style: TextStyle(fontSize: 26)),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Lockdown active', style: hs(16, color: Colors.white)),
            Text('${st.pkgs.length} apps blocked${st.nuclear ? ' · Nuclear' : ''}',
                style: cap(color: Colors.white60)),
          ]),
        ),
        Text(mmss(st.remainingMs ~/ 1000), style: hs(22, color: C.tangerine)),
      ]),
    );
  }
}

/// Warns when the Accessibility blocker isn't enabled.
class A11yWarn extends StatefulWidget {
  const A11yWarn({super.key});
  @override
  State<A11yWarn> createState() => _A11yWarnState();
}

class _A11yWarnState extends State<A11yWarn> {
  Timer? _t;
  bool ok = true;
  @override
  void initState() {
    super.initState();
    _poll();
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _poll());
  }
  Future<void> _poll() async {
    final v = await Native.isA11yEnabled();
    if (mounted && v != ok) setState(() => ok = v);
  }
  @override
  void dispose() { _t?.cancel(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    if (ok) return const SizedBox.shrink();
    return Bento(
      color: C.butter,
      child: Row(children: [
        const Text('⚠️', style: TextStyle(fontSize: 24)),
        const SizedBox(width: 12),
        Expanded(child: Text('Enable the FocusGuard blocker (Accessibility) so locks can close distraction apps.',
            style: cap(color: C.ink, size: 13.5))),
        const SizedBox(width: 8),
        InkBtn('Enable', onTap: Native.openA11y),
      ]),
    );
  }
}

/// Bottom sheet to choose distraction apps.
class AppPicker extends StatefulWidget {
  final List<String> selected;
  const AppPicker({super.key, required this.selected});
  @override
  State<AppPicker> createState() => _AppPickerState();
}

class _AppPickerState extends State<AppPicker> {
  List<AppInfo> all = [];
  late Set<String> sel;
  String q = '';
  bool loading = true;
  @override
  void initState() {
    super.initState();
    sel = widget.selected.toSet();
    Native.apps().then((a) { if (mounted) setState(() { all = a; loading = false; }); });
  }
  @override
  Widget build(BuildContext context) {
    final list = all.where((a) => a.label.toLowerCase().contains(q.toLowerCase())).toList();
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.8,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Pick distraction apps', style: hs(20)),
                const SizedBox(height: 10),
                TextField(
                  decoration: const InputDecoration(hintText: 'Search apps', prefixIcon: Icon(Icons.search)),
                  onChanged: (v) => setState(() => q = v),
                ),
              ]),
            ),
            Expanded(
              child: loading
                  ? const Center(child: CircularProgressIndicator())
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) {
                        final a = list[i];
                        return CheckboxListTile(
                          value: sel.contains(a.pkg),
                          title: Text(a.label, style: const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(a.pkg, style: cap(size: 11)),
                          activeColor: C.btn,
                          onChanged: (v) => setState(() { v == true ? sel.add(a.pkg) : sel.remove(a.pkg); }),
                        );
                      }),
            ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: InkBtn('Save ${sel.length} apps', wide: true,
                  onTap: () => Navigator.pop(context, sel.toList())),
            ),
          ]),
        ),
      ),
    );
  }
}
