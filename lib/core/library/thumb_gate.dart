import 'dart:async';

/// Pause/resume state machine for background thumbnailing.
///
/// Thumbnailing stops the moment the visible player starts playing and only
/// resumes [resumeDelay] after playback pauses or stops, so the hidden
/// decoder never competes with real playback. Pure Dart, no media_kit.
class ThumbGate {
  ThumbGate({this.resumeDelay = const Duration(seconds: 3)});

  final Duration resumeDelay;

  bool _playing = false;
  bool _allowed = true;
  bool _closed = false;
  Timer? _timer;
  Completer<void>? _waiter;

  /// True when background work may run right now.
  bool get allowed => _allowed;
  bool get playing => _playing;

  /// Called whenever the visible player's playing state changes.
  void setPlaying(bool playing) {
    if (_closed || playing == _playing) return;
    _playing = playing;
    _timer?.cancel();
    _timer = null;
    if (playing) {
      _allowed = false;
    } else {
      _timer = Timer(resumeDelay, () {
        _timer = null;
        _allowed = true;
        _release();
      });
    }
  }

  /// Completes immediately when [allowed], otherwise once work may resume
  /// (or the gate is closed). Callers must re-check their own disposed flag.
  Future<void> whenAllowed() {
    if (_allowed || _closed) return Future<void>.value();
    return (_waiter ??= Completer<void>()).future;
  }

  void _release() {
    final w = _waiter;
    _waiter = null;
    if (w != null && !w.isCompleted) w.complete();
  }

  /// Permanently opens the gate so nothing stays blocked during shutdown.
  void close() {
    _closed = true;
    _timer?.cancel();
    _timer = null;
    _allowed = true;
    _release();
  }
}
