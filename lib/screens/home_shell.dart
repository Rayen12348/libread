import 'package:flutter/material.dart';

import '../services/importer.dart';
import '../widgets/sakura_background.dart';
import 'discover_screen.dart';
import 'library_screen.dart';
import 'notes_screen.dart';
import 'settings_screen.dart';

/// The app's root: four tabs over a persistent download indicator.
class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  final _importer = Importer.instance;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _importer.addListener(_onChanged);
  }

  @override
  void dispose() {
    _importer.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  /// Lets the library's "Find books" button jump to the Discover tab.
  void _goToDiscover() => setState(() => _index = 1);

  @override
  Widget build(BuildContext context) {
    final downloading = _importer.active.length;

    return Scaffold(
      // The sakura backdrop sits behind every tab; the tab scaffolds are
      // transparent so it shows through their content.
      body: Stack(
        children: [
          const Positioned.fill(child: SakuraBackground()),
          // Keeps reader state and scroll positions alive across tab switches.
          IndexedStack(
            index: _index,
            children: [
              LibraryScreen(onDiscover: _goToDiscover),
              const DiscoverScreen(),
              const NotesScreen(),
              const SettingsScreen(),
            ],
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: [
          const NavigationDestination(
            icon: Icon(Icons.auto_stories_outlined),
            selectedIcon: Icon(Icons.auto_stories),
            label: 'Library',
          ),
          NavigationDestination(
            icon: Badge(
              isLabelVisible: downloading > 0,
              label: Text('$downloading'),
              child: const Icon(Icons.travel_explore_outlined),
            ),
            selectedIcon: Badge(
              isLabelVisible: downloading > 0,
              label: Text('$downloading'),
              child: const Icon(Icons.travel_explore),
            ),
            label: 'Discover',
          ),
          const NavigationDestination(
            icon: Icon(Icons.edit_note_outlined),
            selectedIcon: Icon(Icons.edit_note),
            label: 'Notes',
          ),
          const NavigationDestination(
            icon: Icon(Icons.tune_outlined),
            selectedIcon: Icon(Icons.tune),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
