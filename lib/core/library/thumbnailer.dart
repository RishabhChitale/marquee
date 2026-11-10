import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart'
    show VideoController, VideoControllerConfiguration;
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'library_logic.dart';
import 'source_detector.dart';
import 'thumb_gate.dart';

Uint8List _shrinkJpeg(Uint8List bytes) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) return bytes;
  final resized = decoded.width > 480
      ? img.copyResize(decoded, width: 480)
      : decoded;
  return Uint8List.fromList(img.encodeJpg(resized, quality: 80));
}

/// Generates thumbnails + metadata with a hidden, muted player, one file at a
/// time. Failures leave thumbnail_path null and move on.
class Thumbnailer {
  Thumbnailer(this.db, this.thumbsDir, {ThumbGate? gate})
    : gate = gate ?? ThumbGate();
  final AppDatabase db;
  final String thumbsDir;

  /// Pauses work while the visible player is playing.
  final ThumbGate gate;

  Player? _player;
  // ignore: unused_field
  VideoController? _controller; // headless; needed so mpv renders a frame
  bool _running = false;
  bool _disposed = false;
  final Set<int> _failed = {};
  final Set<int> _sourceFailed = {};

  /// Kicks off processing of every video lacking a thumbnail. Safe to call
  /// repeatedly; only one loop runs at a time.
  Future<void> processPending() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      await Directory(thumbsDir).create(recursive: true);
      while (!_disposed) {
        if (!gate.allowed) {
          // Free the hidden decoder while real playback runs.
          await _closePlayer();
          await gate.whenAllowed();
          continue;
        }
        final next =
            await (db.select(db.videos)
                  ..where(
                    (t) =>
                        t.thumbnailPath.isNull() &
                        t.missing.equals(false) &
                        t.id.isNotIn(_failed),
                  )
                  ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (next != null) {
          final ok = await _one(next)
              .timeout(const Duration(seconds: 10), onTimeout: () => false)
              .catchError((_) => false);
          if (!ok) _failed.add(next.id);
          continue;
        }
        // Thumbnails done: backfill download-source info once per video.
        final src =
            await (db.select(db.videos)
                  ..where(
                    (t) =>
                        t.sourceChecked.equals(false) &
                        t.missing.equals(false) &
                        t.id.isNotIn(_sourceFailed),
                  )
                  ..orderBy([(t) => OrderingTerm.desc(t.addedAt)])
                  ..limit(1))
                .getSingleOrNull();
        if (src == null) break;
        final ok = await _sourceOnly(src)
            .timeout(const Duration(seconds: 10), onTimeout: () => false)
            .catchError((_) => false);
        if (!ok) _sourceFailed.add(src.id);
      }
    } finally {
      _running = false;
      await _closePlayer();
    }
  }

  Future<Player> _ensurePlayer() async {
    var pl = _player;
    if (pl == null) {
      pl = Player();
      _player = pl;
      pl.setVolume(0);
      final native = pl.platform;
      if (native is NativePlayer) {
        // Thumbnails need neither audio nor subtitles; keep decoding cheap.
        for (final o in const {
          'aid': 'no',
          'sid': 'no',
          'hwdec': 'auto-safe',
        }.entries) {
          try {
            await native.setProperty(o.key, o.value);
          } catch (_) {}
        }
      }
      _controller = VideoController(
        pl,
        configuration: const VideoControllerConfiguration(
          width: 480,
          height: 270,
        ),
      );
    }
    return pl;
  }

  Future<void> _closePlayer() async {
    final pl = _player;
    _player = null;
    _controller = null;
    if (pl == null) return;
    try {
      await pl.stop().timeout(const Duration(seconds: 2));
    } catch (_) {}
    try {
      await pl.dispose().timeout(const Duration(seconds: 2));
    } catch (_) {}
  }

  static const _tagKeys = [
    'purl',
    'comment',
    'description',
    'synopsis',
    'url',
    'website',
  ];

  /// URLs found in container tags of the currently open file (read-only).
  Future<List<String>> _tagUrls(Player pl) async {
    final native = pl.platform;
    final vals = <String?>[];
    if (native is NativePlayer) {
      for (final k in _tagKeys) {
        try {
          vals.add(await native.getProperty('metadata/by-key/$k'));
        } catch (_) {}
      }
    }
    return urlsFromText(vals);
  }

  /// Source for a file that is not otherwise being opened: file attribute
  /// first, container tags only when that finds nothing usable.
  Future<bool> _sourceOnly(Video v) async {
    if (!File(v.path).existsSync()) return false;
    var found = pickSource(await readDownloadOrigin(v.path));
    if (found == null || domainIsCdn(found.domain)) {
      final pl = await _ensurePlayer();
      await pl.open(Media(v.path), play: false);
      await pl.stream.duration.firstWhere((d) => d > Duration.zero);
      final viaTags = pickSource(await _tagUrls(pl));
      if (viaTags != null) found = viaTags;
    }
    await db.setSource(v.id, found?.url, found?.domain);
    return true;
  }

  Future<bool> _one(Video v) async {
    if (!File(v.path).existsSync()) return false;
    final pl = await _ensurePlayer();
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
    final source = pickSource([
      ...await readDownloadOrigin(v.path),
      ...await _tagUrls(pl),
    ]);

    var seekTo = Duration(milliseconds: (dur.inMilliseconds * 0.1).round());
    if (seekTo < const Duration(seconds: 1)) {
      seekTo = const Duration(seconds: 1);
    }
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
        sourceUrl: Value(source?.url),
        sourceDomain: Value(source?.domain),
        sourceChecked: const Value(true),
      ),
    );
    return thumbPath != null;
  }

  Future<void> dispose() async {
    _disposed = true;
    gate.close();
    await _closePlayer();
  }
}
