import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';

import 'shutdown.dart';

/// Makes every quit path (red close button, Cmd-Q, Windows close) dispose all
/// mpv players BEFORE the Flutter engine shuts down.
class WindowLifecycle with WindowListener {
  WindowLifecycle._();

  static const _channel = MethodChannel('marquee/lifecycle');

  static Future<void> install() async {
    final l = WindowLifecycle._();
    await windowManager.setPreventClose(true);
    windowManager.addListener(l);
    // macOS Cmd-Q: AppDelegate answers .terminateLater, then asks us here.
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'willQuit') await AppShutdown.run();
      return null;
    });
  }

  @override
  void onWindowClose() async {
    await AppShutdown.run();
    await windowManager.destroy();
  }
}
