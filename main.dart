import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'store.dart';
import 'theme.dart';
import 'study_tab.dart';
import 'revise_tab.dart';
import 'stats_tab.dart';
import 'rules_tab.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: FocusGuardApp()));
}

class FocusGuardApp extends StatelessWidget {
  const FocusGuardApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
        title: 'FocusGuard',
        debugShowCheckedModeBanner: false,
        theme: buildTheme(),
        home: const Shell(),
      );
}

class Shell extends ConsumerStatefulWidget {
  const Shell({super.key});
  @override
  ConsumerState<Shell> createState() => _ShellState();
}

class _ShellState extends ConsumerState<Shell> {
  int tab = 0;

  @override
  Widget build(BuildContext context) {
    final st = ref.watch(storeProvider);
    if (!st.ready) {
      return const Scaffold(body: Center(child: CircularProgressIndicator(color: C.tangerine)));
    }
    final due = st.dueCount;
    return Scaffold(
      body: SafeArea(
        child: IndexedStack(index: tab, children: const [StudyTab(), ReviseTab(), StatsTab(), RulesTab()]),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: [
          const NavigationDestination(icon: Icon(Icons.timer_outlined), selectedIcon: Icon(Icons.timer), label: 'Study'),
          NavigationDestination(
            icon: Badge(label: Text('$due'), isLabelVisible: due > 0, child: const Icon(Icons.style_outlined)),
            selectedIcon: Badge(label: Text('$due'), isLabelVisible: due > 0, child: const Icon(Icons.style)),
            label: 'Revise',
          ),
          const NavigationDestination(icon: Icon(Icons.bar_chart_outlined), selectedIcon: Icon(Icons.bar_chart), label: 'Stats'),
          const NavigationDestination(icon: Icon(Icons.shield_outlined), selectedIcon: Icon(Icons.shield), label: 'Rules'),
        ],
      ),
    );
  }
}
