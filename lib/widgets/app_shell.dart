import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Left NavigationRail (Library, Playlists, Collections, Now Playing) around the routed page.
class AppShell extends StatelessWidget {
  const AppShell({super.key, required this.location, required this.child});

  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    const routes = ['/library', '/playlists', '/collections', '/player'];
    final found = routes.indexWhere(location.startsWith);
    final onSettings = location.startsWith('/settings');
    final index = found < 0 ? 0 : found;
    return Scaffold(
      body: Row(
        children: [
          NavigationRail(
            selectedIndex: onSettings ? null : index,
            trailing: Expanded(
              child: Align(
                alignment: Alignment.bottomCenter,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: IconButton(
                    tooltip: 'Settings',
                    isSelected: onSettings,
                    icon: const Icon(Icons.settings_outlined),
                    selectedIcon: const Icon(Icons.settings),
                    onPressed: () => context.go('/settings'),
                  ),
                ),
              ),
            ),
            labelType: NavigationRailLabelType.all,
            onDestinationSelected: (i) =>
                context.go(routes[i]),
            destinations: const [
              NavigationRailDestination(
                icon: Icon(Icons.video_library_outlined),
                selectedIcon: Icon(Icons.video_library),
                label: Text('Library'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.queue_music_outlined),
                selectedIcon: Icon(Icons.queue_music),
                label: Text('Playlists'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.collections_bookmark_outlined),
                selectedIcon: Icon(Icons.collections_bookmark),
                label: Text('Collections'),
              ),
              NavigationRailDestination(
                icon: Icon(Icons.play_circle_outline),
                selectedIcon: Icon(Icons.play_circle),
                label: Text('Now Playing'),
              ),
            ],
          ),
          const VerticalDivider(width: 1),
          Expanded(child: child),
        ],
      ),
    );
  }
}
