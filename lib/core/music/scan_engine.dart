import 'dart:async';

import '../library/thumb_gate.dart';
import 'audd_client.dart';
import 'clip_extractor.dart';
import 'dedupe.dart';
import 'sampling.dart';

class ScanVideo {
  const ScanVideo(this.id, this.path, this.durationMs);
  final int id;
  final String path;
  final int durationMs;
}

/// A recognised song with the offset it was heard at.
class FoundSong {
  const FoundSong(this.offsetMs, this.match);
  final int offsetMs;
  final AuddMatch match;
}

/// Where results go (the database in the app, a fake in tests).
abstract class ScanSink {
  Future<void> save(int videoId, List<FoundSong> songs, {required bool failed});
}

typedef Recognizer = Future<AuddMatch?> Function(
    List<int> wav, String token);

enum ScanPhase { idle, running, paused, done, cancelled, stopped }

class ScanProgress {
  const ScanProgress(this.phase, this.done, this.total, {this.error});
  final ScanPhase phase;
  final int done;
  final int total;

  /// AudD's message when the scan was stopped by a token/quota error.
  final String? error;
}

/// Sequential scan: one request at a time, [gap] between requests, paused
/// while the visible player plays (via [gate]), a network error retries the
/// clip once and then marks it failed, a fatal AudD error stops everything.
class ScanEngine {
  ScanEngine({
    required this.source,
    required this.recognize,
    required this.sink,
    required this.token,
    required this.clipCount,
    ThumbGate? gate,
    this.gap = const Duration(milliseconds: 300),
    this.onProgress,
  }) : gate = gate ?? ThumbGate();

  final ClipSource source;
  final Recognizer recognize;
  final ScanSink sink;
  final String token;
  final int clipCount;
  final ThumbGate gate;
  final Duration gap;
  final void Function(ScanProgress)? onProgress;

  ScanPhase _phase = ScanPhase.idle;
  bool _cancel = false;
  Completer<void>? _resume;
  int _done = 0;
  int _total = 0;
  String? _error;

  ScanPhase get phase => _phase;
  int get done => _done;
  int get total => _total;

  void _emit() =>
      onProgress?.call(ScanProgress(_phase, _done, _total, error: _error));

  void pause() {
    if (_phase != ScanPhase.running) return;
    _phase = ScanPhase.paused;
    _resume = Completer<void>();
    _emit();
  }

  void resume() {
    if (_phase != ScanPhase.paused) return;
    _phase = ScanPhase.running;
    final r = _resume;
    _resume = null;
    if (r != null && !r.isCompleted) r.complete();
    _emit();
  }

  void cancel() {
    _cancel = true;
    final r = _resume;
    _resume = null;
    if (r != null && !r.isCompleted) r.complete();
  }

  Future<bool> _checkpoint() async {
    while (true) {
      if (_cancel) return false;
      final r = _resume;
      if (r != null) {
        await r.future;
        continue;
      }
      if (!gate.allowed) {
        await gate.whenAllowed();
        continue;
      }
      return true;
    }
  }

  Future<ScanProgress> run(List<ScanVideo> videos) async {
    final plans = <ScanVideo, List<ClipPlan>>{};
    for (final v in videos) {
      final p = planClips(v.durationMs, clipCount);
      if (p.isNotEmpty) plans[v] = p;
    }
    _total = plans.values.fold(0, (a, b) => a + b.length);
    _done = 0;
    _phase = ScanPhase.running;
    _emit();

    outer:
    for (final entry in plans.entries) {
      final v = entry.key;
      final found = <FoundSong>[];
      var failedClips = 0;
      for (final clip in entry.value) {
        if (!await _checkpoint()) break outer;
        var attempts = 0;
        while (true) {
          attempts++;
          try {
            final wav =
                await source.extract(v.path, clip.offsetMs, clip.lengthMs);
            if (wav == null) {
              failedClips++;
              break;
            }
            final m = await recognize(wav, token);
            if (m != null) found.add(FoundSong(clip.offsetMs, m));
            break;
          } on AuddApiError catch (e) {
            if (e.fatal) {
              _error = e.message;
              _phase = ScanPhase.stopped;
              _emit();
              return ScanProgress(_phase, _done, _total, error: _error);
            }
            failedClips++;
            break;
          } on AuddNetworkError {
            if (attempts < 2) continue;
            failedClips++;
            break;
          }
        }
        _done++;
        _emit();
        if (!_cancel) await Future<void>.delayed(gap);
      }
      if (_cancel) break;
      final deduped = dedupeHits(found.map((f) =>
          SongHit(f.offsetMs, f.match.artist, f.match.title, f)));
      await sink.save(
        v.id,
        [for (final h in deduped) h.data as FoundSong],
        failed: failedClips == entry.value.length,
      );
    }
    _phase = _cancel ? ScanPhase.cancelled : ScanPhase.done;
    _emit();
    return ScanProgress(_phase, _done, _total);
  }
}
