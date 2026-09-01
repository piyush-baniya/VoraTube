import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/library/presentation/screens/home_screen.dart';
import '../features/library/presentation/screens/library_screen.dart';
import '../features/playlists/presentation/screens/playlists_screen.dart';
import '../features/player/presentation/widgets/mini_player.dart';
import '../features/search/presentation/screens/search_screen.dart';
import '../features/settings/presentation/screens/settings_screen.dart';
import '../features/player/presentation/providers/sleep_timer_provider.dart';
import '../features/player/presentation/widgets/sleep_timer_sheet.dart';
import 'widgets/glass_nav_bar.dart';

/// The app shell: a tabbed scaffold with a persistent [MiniPlayer].
///
/// Tab bodies live inside a nested [Navigator] so drilled-down routes (playlist
/// details, playlist details, statistics, genres, smart mixes, filtered songs)
/// still render under the single persistent [MiniPlayer].
class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell>
    with WidgetsBindingObserver {
  static const int _libraryIndex = 1;

  /// The nested navigator hosting tab content and every pushed detail route.
  /// Backwards pops are delegated to it by [NavigatorPopHandler].
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  /// Mirrors the selected tab. A notifier instead of plain state so the tab
  /// index can drive both the bottom bar and the nested navigator's base route
  /// without rebuilding either subtree on unrelated shell changes.
  final ValueNotifier<int> _tabIndex = ValueNotifier<int>(0);

  /// Guards against showing the sleep-timer-finished popup more than once for
  /// the same finished episode (e.g. if the provider flips back to finished
  /// during a foreground transition).
  bool _handlingTimerFinished = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Surface the sleep-timer-finished popup the moment the timer expires
    // while the app is in the foreground.
    ref.listenManual<SleepTimerState>(sleepTimerProvider, (previous, next) {
      if (next.isFinished) _maybeShowSleepTimerFinished();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // If the timer expired while the app was backgrounded or the screen was
    // off, surface the popup when the user returns to the foreground.
    if (state == AppLifecycleState.resumed) {
      _maybeShowSleepTimerFinished();
    }
  }

  /// Shows the "Sleep Timer Finished" popup exactly once per finished episode,
  /// only while the app is actually visible. Dismissing clears the state so it
  /// never reappears by itself.
  void _maybeShowSleepTimerFinished() {
    if (_handlingTimerFinished) return;
    if (!mounted) return;
    // Only surface while the app is on screen. If the timer expired while the
    // app was backgrounded or the screen was off, the lifecycle-resume handler
    // picks it up on the way back to the foreground — never show into a hidden
    // UI.
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    if (!ref.read(sleepTimerProvider).isFinished) return;
    _handlingTimerFinished = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await showSleepTimerFinishedDialog(context);
      ref.read(sleepTimerProvider.notifier).dismissFinished();
      _handlingTimerFinished = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabIndex.dispose();
    super.dispose();
  }

  void _onDestinationSelected(int index) {
    final navigator = _navigatorKey.currentState;
    if (index == _tabIndex.value) {
      // Re-tapping the active tab still returns to the tab root, abandoning
      // any drilled-down detail route.
      navigator?.popUntil((route) => route.isFirst);
      return;
    }
    // Detail routes (playlist detail, genre detail, smart mixes, statistics…)
    // are pushed on top of the tab host inside the nested navigator. They must
    // not sit in front of the navigation system when the user switches tabs:
    // pop back to the base route so the newly selected top-level screen is
    // immediately visible and Back no longer reveals the abandoned detail.
    if (navigator != null && navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
    _tabIndex.value = index;
  }

  /// Screens held by the [IndexedStack] hosted on the nested navigator's base
  /// route. Search is passed an [onBack] that returns to the Library tab:
  /// Search lives as a tab (not a pushed route), so popping the navigator
  /// would blank the whole app.
  List<Widget> get _screens => [
    HomeScreen(onSeeAllSongs: () => _onDestinationSelected(_libraryIndex)),
    const LibraryScreen(),
    SearchScreen(onBack: () => _onDestinationSelected(_libraryIndex)),
    const PlaylistsScreen(),
    const SettingsScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Expanded(
            child: NavigatorPopHandler(
              onPopWithResult: (_) => _navigatorKey.currentState?.pop(),
              // The nested navigator is the tab root. Whenever it can pop (a
              // detail route is open) the handler claims the system back
              // button and pops that route; otherwise back bubbles to the root
              // navigator, which owns the full player and app exit.
              child: Navigator(
                key: _navigatorKey,
                onGenerateRoute: (settings) => MaterialPageRoute(
                  settings: settings,
                  builder: (_) =>
                      _TabsHost(index: _tabIndex, screens: _screens),
                ),
              ),
            ),
          ),
          // Persistent across every tab and detail route: this sits outside the
          // nested navigator, so pushed routes cannot cover it.
          const MiniPlayer(),
        ],
      ),
      bottomNavigationBar: ValueListenableBuilder<int>(
        valueListenable: _tabIndex,
        builder: (context, index, _) => GlassNavBar(
          currentIndex: index,
          onDestinationSelected: _onDestinationSelected,
          destinations: const [
            GlNavDestination(
              icon: Icons.home_outlined,
              selectedIcon: Icons.home,
              label: 'Home',
            ),
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
      ),
    );
  }
}

/// The lazy, state-preserving tab body shown on the nested navigator's base
/// route.
///
/// [IndexedStack] builds every child eagerly, which runs each screen's
/// `initState` at launch — that made Search grab focus and open the keyboard
/// over the Library, and paid the cost of every screen's providers before the
/// user had asked for any of them. Building a tab only once it is first
/// selected avoids both, while [IndexedStack] still preserves its state for
/// every subsequent visit.
class _TabsHost extends StatefulWidget {
  const _TabsHost({required this.index, required this.screens});

  final ValueNotifier<int> index;
  final List<Widget> screens;

  @override
  State<_TabsHost> createState() => _TabsHostState();
}

class _TabsHostState extends State<_TabsHost> {
  /// Tabs that have been opened at least once.
  final Set<int> _visited = {0};

  @override
  void initState() {
    super.initState();
    widget.index.addListener(_onIndexChanged);
  }

  @override
  void didUpdateWidget(_TabsHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      oldWidget.index.removeListener(_onIndexChanged);
      widget.index.addListener(_onIndexChanged);
    }
  }

  @override
  void dispose() {
    widget.index.removeListener(_onIndexChanged);
    super.dispose();
  }

  void _onIndexChanged() {
    if (!mounted) return;
    setState(() => _visited.add(widget.index.value));
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: widget.index,
      builder: (context, index, _) => IndexedStack(
        index: index,
        children: <Widget>[
          for (var i = 0; i < widget.screens.length; i++)
            if (_visited.contains(i))
              widget.screens[i]
            else
              const SizedBox.shrink(),
        ],
      ),
    );
  }
}
