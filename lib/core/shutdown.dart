import 'dart:async';

/// Ordered, idempotent app shutdown. Everything that owns an mpv instance
/// registers here so ALL players are stopped and disposed before the Flutter
/// engine (and its Metal pipelines) is torn down.
class AppShutdown {
  AppShutdown._();

  static final List<Future<void> Function()> _steps = [];
  static Future<void>? _running;

  /// Steps run in registration order, each with a 2 s timeout. [first] puts
  /// a step ahead of the rest (the thumbnailer must stop before players do).
  static void register(Future<void> Function() step, {bool first = false}) =>
      first ? _steps.insert(0, step) : _steps.add(step);

  static Future<void> run() => _running ??= _run();

  static Future<void> _run() async {
    for (final step in List.of(_steps)) {
      try {
        await step().timeout(const Duration(seconds: 2));
      } catch (_) {
        // A stuck or failing step must not block the others or the quit.
      }
    }
  }
}
