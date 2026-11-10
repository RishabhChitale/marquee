import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/library/library_providers.dart';
import 'features/library/library_screen.dart';
import 'features/player/player_screen.dart';
import 'widgets/app_shell.dart';

final GoRouter _router = GoRouter(
  initialLocation: '/library',
  routes: [
    ShellRoute(
      builder: (context, state, child) =>
          AppShell(location: state.uri.path, child: child),
      routes: [
        GoRoute(
          path: '/library',
          builder: (context, state) => const LibraryScreen(),
        ),
        GoRoute(
          path: '/player',
          builder: (context, state) => const PlayerScreen(),
        ),
      ],
    ),
  ],
);

class MarqueeApp extends ConsumerStatefulWidget {
  const MarqueeApp({super.key});

  @override
  ConsumerState<MarqueeApp> createState() => _MarqueeAppState();
}

class _MarqueeAppState extends ConsumerState<MarqueeApp> {
  @override
  void initState() {
    super.initState();
    Future.microtask(() {
      ref.read(playbackTrackerProvider); // start resume tracking
      ref.read(libraryServiceProvider.notifier).start(); // scan on launch
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp.router(
      title: 'Marquee',
      debugShowCheckedModeBanner: false,
      themeMode: ThemeMode.dark,
      theme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.dark,
        useMaterial3: true,
      ),
      routerConfig: _router,
    );
  }
}
