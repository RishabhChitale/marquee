import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:media_kit/media_kit.dart';
import 'package:path/path.dart' as p;

/// Cuts a WAV clip out of a video's audio.
abstract class ClipSource {
  /// Returns the WAV bytes, or null when no audio could be produced.
  Future<Uint8List?> extract(String path, int offsetMs, int lengthMs);
  Future<void> dispose();
}

/// Uses a separate hidden media_kit player with mpv's PCM audio output
/// (ao=pcm) so no ffmpeg is needed. The temp WAV is deleted right after it is
/// read; the video file is only ever opened for reading.
class MpvClipSource implements ClipSource {
  MpvClipSource(this.tempDir);
  final String tempDir;

  Player? _player;
  bool _disposed = false;

  @override
  Future<Uint8List?> extract(String path, int offsetMs, int lengthMs) async {
    if (_disposed) return null;
    await Directory(tempDir).create(recursive: true);
    final out = File(p.join(tempDir, 'clip.wav'));
    if (await out.exists()) await out.delete();
    final player = Player();
    _player = player;
    try {
      final native = player.platform as NativePlayer;
      Future<void> set(String k, String v) => native.setProperty(k, v);
      await set('vid', 'no');
      await set('sid', 'no');
      await set('ao', 'pcm');
      await set('ao-pcm-file', out.path);
      await set('ao-pcm-waveheader', 'yes');
      await set('untimed', 'yes');
      await set('start', (offsetMs / 1000).toStringAsFixed(3));
      await set('length', (lengthMs / 1000).toStringAsFixed(3));
      await set('audio-channels', 'mono');
      await set('audio-samplerate', '16000');
      final done = Completer<void>();
      final subs = <StreamSubscription<dynamic>>[
        player.stream.completed.listen((c) {
          if (c && !done.isCompleted) done.complete();
        }),
        player.stream.error.listen((_) {
          if (!done.isCompleted) done.complete();
        }),
      ];
      try {
        await player.open(Media(path));
        await done.future.timeout(const Duration(seconds: 60));
      } on TimeoutException {
        return null;
      } finally {
        for (final s in subs) {
          await s.cancel();
        }
      }
      await player.dispose();
      _player = null;
      if (!await out.exists()) return null;
      final bytes = await out.readAsBytes();
      // Header only (no audio) means the file has no audio track.
      return bytes.length > 4000 ? bytes : null;
    } catch (_) {
      return null;
    } finally {
      if (_player != null) {
        try {
          await player.dispose();
        } catch (_) {}
        _player = null;
      }
    }
  }

  /// Deletes the temp WAV (call right after the upload).
  Future<void> cleanup() async {
    final f = File(p.join(tempDir, 'clip.wav'));
    try {
      if (await f.exists()) await f.delete();
    } catch (_) {}
  }

  @override
  Future<void> dispose() async {
    _disposed = true;
    final pl = _player;
    _player = null;
    if (pl != null) {
      try {
        await pl.dispose();
      } catch (_) {}
    }
    await cleanup();
  }
}
