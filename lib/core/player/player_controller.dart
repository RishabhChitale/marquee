import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import '../shutdown.dart';
import 'play_queue.dart';

/// Wraps a media_kit [Player] with a simple play queue.
class PlayerController {
  PlayerController() {
    player = Player();
    // Hardware decode; texture size stays the video's own (no width/height).
    final native = player.platform;
    if (native is NativePlayer) {
      unawaited(native.setProperty('hwdec', 'auto-safe'));
    }
    video = VideoController(
      player,
      configuration:
          const VideoControllerConfiguration(enableHardwareAcceleration: true),
    );
    AppShutdown.register(dispose);
    player.stream.completed.listen((done) {
      if (done) next();
    });
  }

  late final Player player;
  late final VideoController video;
  final PlayQueue queue = PlayQueue();

  final _opened = StreamController<String>.broadcast();

  /// Emits the path every time a new file starts (open, next, previous).
  Stream<String> get opened => _opened.stream;

  Future<void> open(String path, {Duration? start}) async {
    queue.select(path);
    _opened.add(path);
    await player.open(Media(path, start: start));
  }

  /// Queues [paths] in order and starts at [startPath], or at [startIndex]
  /// when given (needed when the same file appears twice in a playlist).
  Future<void> playList(List<String> paths, String startPath,
      {Duration? start, int? startIndex}) async {
    final i = startIndex ?? paths.indexOf(startPath);
    queue.setItems(paths, start: i);
    final path = paths.isEmpty ? startPath : paths[queue.index];
    _opened.add(path);
    await player.open(Media(path, start: start));
  }

  Future<void> play() => player.play();
  Future<void> pause() => player.pause();
  Future<void> playOrPause() => player.playOrPause();
  Future<void> seek(Duration position) => player.seek(position);

  /// Seeks relative to the current position, clamped to the media length.
  Future<void> seekBy(Duration delta) {
    final target = player.state.position + delta;
    final max = player.state.duration;
    final clamped = target < Duration.zero
        ? Duration.zero
        : (max > Duration.zero && target > max ? max : target);
    return player.seek(clamped);
  }

  /// [volume] is 0-100.
  Future<void> setVolume(double volume) =>
      player.setVolume(volume.clamp(0, 100).toDouble());
  Future<void> setRate(double rate) => player.setRate(rate);

  Future<void> next() async {
    final p = queue.next();
    if (p != null) {
      _opened.add(p);
      await player.open(Media(p));
    }
  }

  Future<void> previous() async {
    final p = queue.previous();
    if (p != null) {
      _opened.add(p);
      await player.open(Media(p));
    }
  }

  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// Audio tracks currently available (includes auto/no entries).
  List<AudioTrack> get audioTracks => player.state.tracks.audio;
  List<SubtitleTrack> get subtitleTracks => player.state.tracks.subtitle;

  bool _disposed = false;

  /// Stops, then disposes, the mpv instance. Safe to call twice.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    try {
      await player.stop();
    } catch (_) {}
    await player.dispose();
  }
}

final playerControllerProvider = Provider<PlayerController>((ref) {
  final c = PlayerController();
  ref.onDispose(c.dispose);
  return c;
});
