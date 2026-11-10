import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart' show VideoController;
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'library_logic.dart';

Uint8List _shrinkJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized =
      decoded.width > 480 ? img.copyResize(decoded, width: 480) : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

/// Generates thumbnails + metadata with a hidden, muted player, one file at a
/// time. Failures leave thumbnail_path null and move on.
class Thumbnailer {
  Thumbnailer(this.db, this.thumbsDir);
  final AppDatabase db;
  final String thumbsDir;

  Player? _player;
  // ignore: unused_field
  VideoController? _controller; // headless; needed so mpv renders a frame
  bool _running = false;
  bool _disposed = false;
  final Set<int> _failed = {};

  /// Kicks off processing of every video lacking a thumbnail. Safe to call
  /// repeatedly; only one loop runs at a time.
  Future<void> processPending() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      await Directory(thumbsDir).create(recursive: true);
      while (!_disposed) {
        final next = await (db.select(db.videos)
              ..where((t) =>
                  t.thumbnailPath.isNull() &
                  t.missing.equals(false) &
                  t.id.isNotIn(_failed))
              ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
              ..limit(1))
            .getSingleOrNull();
        if (next == null) break;
        final ok = await _one(next)
            .timeout(const Duration(seconds: 10), onTimeout: () => false)
            .catchError((_) => false);
        if (!ok) _failed.add(next.id);
      }
    } finally {
      _running = false;
      await _closePlayer();
    }
  }

  Player _ensurePlayer() {
    var pl = _player;
    if (pl == null) {
      pl = Player();
      pl.setVolume(0);
      _controller = VideoController(pl);
      _player = pl;
    }
    return pl;
  }

  Future<void> _closePlayer() async {
    final pl = _player;
    _player = null;
    _controller = null;
    await pl?.dispose();
  }

  Future<bool> _one(Video v) async {
    if (!File(v.path).existsSync()) return false;
    final pl = _ensurePlayer();
    await pl.open(Media(v.path), play: false);
    await pl.stream.duration.firstWhere((d) => d > Duration.zero);
    await pl.stream.width.firstWhere((w) => w != null && w > 0);
    final dur = pl.state.duration;
    final w = pl.state.width ?? 0;
    final h = pl.state.height ?? 0;

    DateTime? recorded;
    final native = pl.platform;
    if (native is NativePlayer) {
      for (final key in const [
        'metadata/by-key/com.apple.quicktime.creationdate',
        'metadata/by-key/creation_time',
      ]) {
        try {
          recorded = parseCreationTime(await native.getProperty(key));
        } catch (_) {}
        if (recorded != null) break;
      }
    }
    recorded ??= v.fileModifiedAt;

    var seekTo = Duration(milliseconds: (dur.inMilliseconds * 0.1).round());
    if (seekTo < const Duration(seconds: 1)) seekTo = const Duration(seconds: 1);
    if (seekTo >= dur) seekTo = Duration.zero;
    await pl.seek(seekTo);
    await Future<void>.delayed(const Duration(milliseconds: 400));
    final shot = await pl.screenshot(format: 'image/jpeg');

    String? thumbPath;
    if (shot != null && shot.isNotEmpty) {
      final small = await compute(_shrinkJpeg, shot);
      final file = File(p.join(thumbsDir, '${v.id}.jpg'));
      await file.writeAsBytes(small, flush: true);
      thumbPath = file.path;
    }
    await (db.update(db.videos)..where((t) => t.id.equals(v.id))).write(
      VideosCompanion(
        durationMs: Value(dur.inMilliseconds),
        width: Value(w),
        height: Value(h),
        recordedAt: Value(recorded),
        thumbnailPath: Value(thumbPath),
      ),
    );
    return thumbPath != null;
  }

  Future<void> dispose() async {
    _disposed = true;
    await _closePlayer();
  }
}
