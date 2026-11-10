import 'dart:async';

import 'package:drift/drift.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../db/database.dart';
import '../player/player_controller.dart';
import 'library_logic.dart';
import 'scanner.dart';
import 'thumbnailer.dart';

final databaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase.open();
  ref.onDispose(db.close);
  return db;
});

final videosProvider = StreamProvider<List<Video>>(
    (ref) => ref.watch(databaseProvider).watchVideos());

final foldersProvider = StreamProvider<List<LibraryFolder>>(
    (ref) => ref.watch(databaseProvider).watchFolders());

class SearchQuery extends Notifier<String> {
  @override
  String build() => '';
  void set(String v) => state = v;
}

final searchProvider =
    NotifierProvider<SearchQuery, String>(SearchQuery.new);

class SortChoice extends Notifier<VideoSort> {
  @override
  VideoSort build() => VideoSort.newest;
  void set(VideoSort v) => state = v;
}

final sortProvider = NotifierProvider<SortChoice, VideoSort>(SortChoice.new);

/// The videos currently visible (filtered + sorted).
final visibleVideosProvider = Provider<List<Video>>((ref) {
  final all = ref.watch(videosProvider).value ?? const <Video>[];
  return filterAndSort(
      all, ref.watch(searchProvider), ref.watch(sortProvider));
});

class ScanState {
  const ScanState({this.scanning = false, this.found = 0});
  final bool scanning;
  final int found;
}

class LibraryService extends Notifier<ScanState> {
  Thumbnailer? _thumbs;
  bool _started = false;

  @override
  ScanState build() => const ScanState();

  AppDatabase get _db => ref.read(databaseProvider);

  Future<void> start() async {
    if (_started) return;
    _started = true;
    final dir = await getApplicationSupportDirectory();
    _thumbs = Thumbnailer(_db, p.join(dir.path, 'thumbs'));
    ref.onDispose(() => _thumbs?.dispose());
    await rescan();
  }

  Future<void> rescan() async {
    if (state.scanning) return;
    state = const ScanState(scanning: true);
    try {
      await LibraryScanner(_db).scanAll(
          onProgress: (n) => state = ScanState(scanning: true, found: n));
    } finally {
      state = ScanState(scanning: false, found: state.found);
    }
    unawaited(_thumbs?.processPending());
  }

  Future<void> addFolder(String path) async {
    await _db.into(_db.libraryFolders).insert(
        LibraryFoldersCompanion.insert(path: path, addedAt: DateTime.now()),
        mode: InsertMode.insertOrIgnore);
    await rescan();
  }

  /// Removes the folder and its video rows. Never touches files on disk.
  Future<void> removeFolder(int id) async {
    await (_db.delete(_db.libraryFolders)..where((t) => t.id.equals(id))).go();
    // Foreign keys cascade; delete explicitly too in case pragma is off.
    await (_db.delete(_db.videos)..where((t) => t.folderId.equals(id))).go();
  }

  Future<void> rename(int id, String title) async {
    await (_db.update(_db.videos)..where((t) => t.id.equals(id)))
        .write(VideosCompanion(title: Value(title)));
  }

  /// Removes only the database row.
  Future<void> removeVideo(int id) async {
    await (_db.delete(_db.videos)..where((t) => t.id.equals(id))).go();
  }
}

final libraryServiceProvider =
    NotifierProvider<LibraryService, ScanState>(LibraryService.new);

/// Saves resume position / play count as the player runs.
class PlaybackTracker {
  PlaybackTracker(this.db, this.controller) {
    _subs
      ..add(controller.opened.listen(_onOpened))
      ..add(controller.player.stream.position.listen(_onPosition))
      ..add(controller.player.stream.playing.listen((playing) {
        if (!playing) unawaited(save());
      }))
      ..add(controller.player.stream.completed.listen((done) {
        if (done) unawaited(save(atEnd: true));
      }));
  }

  final AppDatabase db;
  final PlayerController controller;
  final _subs = <StreamSubscription<dynamic>>[];
  int? _videoId;
  int _lastSaveMs = 0;
  bool _counted = false;

  Future<void> _onOpened(String path) async {
    await save(); // previous file
    final v = await (db.select(db.videos)..where((t) => t.path.equals(path)))
        .getSingleOrNull();
    _videoId = v?.id;
    _counted = false;
    _lastSaveMs = DateTime.now().millisecondsSinceEpoch;
    if (v != null) {
      await (db.update(db.videos)..where((t) => t.id.equals(v.id)))
          .write(VideosCompanion(lastPlayedAt: Value(DateTime.now())));
    }
  }

  void _onPosition(Duration _) {
    if (!controller.player.state.playing) return;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastSaveMs >= 5000) unawaited(save());
  }

  Future<void> save({bool atEnd = false}) async {
    final id = _videoId;
    if (id == null) return;
    _lastSaveMs = DateTime.now().millisecondsSinceEpoch;
    final st = controller.player.state;
    final dur = st.duration.inMilliseconds;
    final pos = atEnd ? dur : st.position.inMilliseconds;
    if (dur <= 0 && !atEnd) return;
    final finished = isFinished(pos, dur);
    final bump = finished && !_counted;
    if (finished) _counted = true;
    final row = await (db.select(db.videos)..where((t) => t.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    await (db.update(db.videos)..where((t) => t.id.equals(id))).write(
      VideosCompanion(
        resumePositionMs: Value(finished ? 0 : pos),
        playCount: bump ? Value(row.playCount + 1) : const Value.absent(),
        durationMs: row.durationMs == 0 && dur > 0
            ? Value(dur)
            : const Value.absent(),
      ),
    );
  }

  void dispose() {
    for (final s in _subs) {
      s.cancel();
    }
  }
}

final playbackTrackerProvider = Provider<PlaybackTracker>((ref) {
  final t = PlaybackTracker(
      ref.watch(databaseProvider), ref.watch(playerControllerProvider));
  ref.onDispose(t.dispose);
  return t;
});
