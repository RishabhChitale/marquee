import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';

import 'play_queue.dart';

/// Wraps a media_kit [Player] with a simple play queue.
class PlayerController {
  PlayerController() {
    player = Player();
    video = VideoController(player);
    player.stream.completed.listen((done) {
      if (done) next();
    });
  }

  late final Player player;
  late final VideoController video;
  final PlayQueue queue = PlayQueue();

  Future<void> open(String path) async {
    queue.select(path);
    await player.open(Media(path));
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
    if (p != null) await player.open(Media(p));
  }

  Future<void> previous() async {
    final p = queue.previous();
    if (p != null) await player.open(Media(p));
  }

  Future<void> setAudioTrack(AudioTrack track) => player.setAudioTrack(track);
  Future<void> setSubtitleTrack(SubtitleTrack track) =>
      player.setSubtitleTrack(track);

  /// Audio tracks currently available (includes auto/no entries).
  List<AudioTrack> get audioTracks => player.state.tracks.audio;
  List<SubtitleTrack> get subtitleTracks => player.state.tracks.subtitle;

  Future<void> dispose() => player.dispose();
}

final playerControllerProvider = Provider<PlayerController>((ref) {
  final c = PlayerController();
  ref.onDispose(c.dispose);
  return c;
});
