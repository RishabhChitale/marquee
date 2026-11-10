import Cocoa
import FlutterMacOS

@main
class AppDelegate: FlutterAppDelegate {
  override func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
    return true
  }

  override func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
    return true
  }

  // Cmd-Q / Dock Quit: let Dart stop and dispose every mpv player first, then
  // finish terminating. Without this the engine is torn down while mpv's core
  // thread is still calling back into Dart, which aborts.
  private var quitting = false

  override func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
    if quitting { return .terminateLater }
    guard
      let controller = mainFlutterWindow?.contentViewController as? FlutterViewController
    else {
      return .terminateNow
    }
    quitting = true
    let channel = FlutterMethodChannel(
      name: "marquee/lifecycle", binaryMessenger: controller.engine.binaryMessenger)
    var replied = false
    let finish = {
      if replied { return }
      replied = true
      NSApp.reply(toApplicationShouldTerminate: true)
    }
    channel.invokeMethod("willQuit", arguments: nil) { _ in finish() }
    // Safety net: never hang the quit if Dart doesn't answer.
    DispatchQueue.main.asyncAfter(deadline: .now() + 3) { finish() }
    return .terminateLater
  }
}
