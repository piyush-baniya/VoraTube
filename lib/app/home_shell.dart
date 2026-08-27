import 'package:flutter/material.dart';

import '../features/library/presentation/screens/library_screen.dart';
import '../features/playlists/presentation/screens/playlists_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import 'widgets/glass_nav_bar.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key});

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _currentIndex = 0;

  /// Tabs that have been opened at least once.
  ///
  /// [IndexedStack] builds every child eagerly, which runs each screen's
  /// `initState` at launch — that made Search grab focus and open the keyboard
  /// over the Library, and paid the cost of four screens' providers before the
  /// user had asked for any of them. Building a tab only once it is first
  /// selected avoids both, while [IndexedStack] still preserves its state for
  /// every subsequent visit.
  final Set<int> _visited = {0};

  static const List<Widget> _screens = [
    LibraryScreen(),
    SearchScreen(),
    PlaylistsScreen(),
    SettingsScreen(),
  ];

  void _onDestinationSelected(int index) {
    if (index == _currentIndex) return;
    setState(() {
      _currentIndex = index;
      _visited.add(index);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: IndexedStack(
              index: _currentIndex,
              children: <Widget>[
                for (var i = 0; i < _screens.length; i++)
                  if (_visited.contains(i))
                    _screens[i]
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: GlassNavBar(
        currentIndex: _currentIndex,
        onDestinationSelected: _onDestinationSelected,
        destinations: const [
          GlNavDestination(
            icon: Icons.library_music_outlined,
            selectedIcon: Icons.library_music,
            label: 'Library',
          ),
          GlNavDestination(
            icon: Icons.search_outlined,
            selectedIcon: Icons.search,
            label: 'Search',
          ),
          GlNavDestination(
            icon: Icons.playlist_play_outlined,
            selectedIcon: Icons.playlist_play,
            label: 'Playlists',
          ),
          GlNavDestination(
            icon: Icons.settings_outlined,
            selectedIcon: Icons.settings,
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
