import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../library/library_providers.dart';
import '../library/tags_logic.dart';
import '../library/thumb_gate.dart';
import '../player/player_controller.dart';
import 'audd_client.dart';
import 'clip_extractor.dart';
import 'scan_engine.dart';
import 'token_store.dart';

final musicMatchesProvider = StreamProvider<List<MusicMatch>>(
  (ref) => ref.watch(databaseProvider).watchMusicMatches(),
);

/// videoId -> its matches ordered by offset.
final matchesByVideoProvider = Provider<Map<int, List<MusicMatch>>>((ref) {
  final all = ref.watch(musicMatchesProvider).value ?? const <MusicMatch>[];
  final out = <int, List<MusicMatch>>{};
  for (final m in all) {
    (out[m.videoId] ??= []).add(m);
  }
  for (final l in out.values) {
    l.sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
  }
  return out;
});

final musicIndexProvider = Provider<MusicByVideo>(
  (ref) => buildMusicIndex(
    ref.watch(musicMatchesProvider).value ?? const <MusicMatch>[],
  ),
);

Future<TokenStore> _tokenStore() async {
  final dir = await getApplicationSupportDirectory();
  return TokenStore(
    appSupportDir: dir.path,
    homeDir: Platform.environment['HOME'] ??
        Platform.environment['USERPROFILE'],
  );
}

/// The AudD token (null = none saved). Never logged.
class TokenNotifier extends AsyncNotifier<String?> {
  @override
  Future<String?> build() async => (await _tokenStore()).read();

  Future<void> save(String token) async {
    await (await _tokenStore()).save(token);
    state = AsyncData(token.trim());
  }

  Future<void> remove() async {
    final s = await _tokenStore();
    await s.remove();
    state = AsyncData(await s.read());
  }
}

final auddTokenProvider =
    AsyncNotifierProvider<TokenNotifier, String?>(TokenNotifier.new);

/// Clips per video (1, 2 or 3; default 3), kept in `<app support>/audd_clips`.
class ClipCountNotifier extends AsyncNotifier<int> {
  Future<File> _file() async =>
      File(p.join((await getApplicationSupportDirectory()).path, 'audd_clips'));

  @override
  Future<int> build() async {
    try {
      final n = int.tryParse((await (await _file()).readAsString()).trim());
      if (n != null && n >= 1 && n <= 3) return n;
    } catch (_) {}
    return 3;
  }

  Future<void> set(int n) async {
    state = AsyncData(n);
    await (await _file()).writeAsString('$n');
  }
}

final clipCountProvider =
    AsyncNotifierProvider<ClipCountNotifier, int>(ClipCountNotifier.new);

class _DbSink implements ScanSink {
  _DbSink(this.db);
  final AppDatabase db;
  @override
  Future<void> save(int videoId, List<FoundSong> songs,
      {required bool failed}) {
    final now = DateTime.now();
    return db.saveMusicResult(
      videoId,
      [
        for (final s in songs)
          MusicMatchesCompanion.insert(
            videoId: videoId,
            offsetMs: s.offsetMs,
            artist: s.match.artist,
            title: s.match.title,
            album: Value(s.match.album),
            releaseDate: Value(s.match.releaseDate),
            songLink: Value(s.match.songLink),
            spotifyUrl: Value(s.match.spotifyUrl),
            appleMusicUrl: Value(s.match.appleMusicUrl),
            matchedAt: now,
          ),
      ],
      failed: failed,
    );
  }
}

/// Header progress; null phase = nothing running.
class MusicScanState {
  const MusicScanState([this.progress]);
  final ScanProgress? progress;
  bool get active =>
      progress != null &&
      (progress!.phase == ScanPhase.running ||
          progress!.phase == ScanPhase.paused);
}

class MusicScanController extends Notifier<MusicScanState> {
  ScanEngine? _engine;

  @override
  MusicScanState build() => const MusicScanState();

  bool get paused => _engine?.phase == ScanPhase.paused;

  /// Starts a manual scan of [videos]. Already-scanned videos are skipped
  /// unless [rescan]. Returns false when a scan is already running.
  Future<bool> start(
    List<Video> videos, {
    required String token,
    required int clipCount,
    required bool rescan,
  }) async {
    if (state.active) return false;
    final todo = [
      for (final v in videos)
        if (rescan || v.musicScannedAt == null)
          ScanVideo(v.id, v.path, v.durationMs),
    ];
    final tmp = p.join((await getTemporaryDirectory()).path, 'marquee_music');
    final source = MpvClipSource(tmp);
    final client = AuddClient();
    final gate = ThumbGate();
    final player = ref.read(playerControllerProvider).player;
    gate.setPlaying(player.state.playing);
    final sub = player.stream.playing.listen(gate.setPlaying);
    final engine = ScanEngine(
      source: source,
      recognize: (wav, t) async {
        try {
          return await client.recognize(Uint8List.fromList(wav), t);
        } finally {
          await source.cleanup();
        }
      },
      sink: _DbSink(ref.read(databaseProvider)),
      token: token,
      clipCount: clipCount,
      gate: gate,
      onProgress: (pr) => state = MusicScanState(pr),
    );
    _engine = engine;
    try {
      await engine.run(todo);
    } finally {
      await sub.cancel();
      gate.close();
      client.close();
      await source.dispose();
      _engine = null;
    }
    return true;
  }

  void pause() => _engine?.pause();
  void resume() => _engine?.resume();
  void cancel() => _engine?.cancel();
  void dismiss() => state = const MusicScanState();
}

final musicScanProvider =
    NotifierProvider<MusicScanController, MusicScanState>(
        MusicScanController.new);
