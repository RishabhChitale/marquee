import 'dart:math';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/db/database.dart';
import 'package:marquee/core/library/lists_logic.dart';

import 'library_test.dart' show vid;

void main() {
  late AppDatabase db;
  late int folderId;

  setUp(() async {
    db = AppDatabase(NativeDatabase.memory());
    folderId = await db.into(db.libraryFolders).insert(
        LibraryFoldersCompanion.insert(path: '/x', addedAt: DateTime.now()));
  });
  tearDown(() => db.close());

  Future<List<int>> addVideos(int n) async => [
        for (var i = 1; i <= n; i++)
          await db.into(db.videos).insert(VideosCompanion.insert(
                path: '/x/$i.mp4',
                folderId: folderId,
                fileName: '$i.mp4',
                title: 't$i',
                sizeBytes: 1,
                fileModifiedAt: DateTime(2024, 7, i),
                addedAt: DateTime(2024),
              )),
      ];

  Future<List<int>> playlistVideoIds(int pid) async {
    final rows = await (db.select(db.playlistItems)
          ..where((t) => t.playlistId.equals(pid))
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    return [for (final r in rows) r.videoId];
  }

  test('v1 to v2 migration keeps videos and adds list tables', () async {
    final old = AppDatabase(NativeDatabase.memory(setup: (raw) {
      raw.execute('''CREATE TABLE library_folders (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
        added_at INTEGER NOT NULL)''');
      raw.execute('''CREATE TABLE videos (
        id INTEGER PRIMARY KEY AUTOINCREMENT, path TEXT NOT NULL UNIQUE,
        folder_id INTEGER NOT NULL REFERENCES library_folders (id) ON DELETE CASCADE,
        file_name TEXT NOT NULL, title TEXT NOT NULL, size_bytes INTEGER NOT NULL,
        file_modified_at INTEGER NOT NULL, recorded_at INTEGER,
        duration_ms INTEGER NOT NULL DEFAULT 0, width INTEGER NOT NULL DEFAULT 0,
        height INTEGER NOT NULL DEFAULT 0, thumbnail_path TEXT,
        added_at INTEGER NOT NULL, last_played_at INTEGER,
        resume_position_ms INTEGER NOT NULL DEFAULT 0,
        play_count INTEGER NOT NULL DEFAULT 0,
        missing INTEGER NOT NULL DEFAULT 0 CHECK (missing IN (0, 1)))''');
      raw.execute("INSERT INTO library_folders (path, added_at) VALUES ('/x', 0)");
      raw.execute('''INSERT INTO videos (path, folder_id, file_name, title,
        size_bytes, file_modified_at, added_at)
        VALUES ('/x/a.mp4', 1, 'a.mp4', 'a', 1, 0, 0)''');
      raw.execute('PRAGMA user_version = 1');
    }));
    addTearDown(old.close);
    final vids = await old.select(old.videos).get();
    expect(vids.map((v) => v.title), ['a']);
    final pid = await old.createPlaylist('P');
    await old.addToPlaylist(pid, [vids.single.id]);
    expect(await old.select(old.playlistItems).get(), hasLength(1));
    final cid = await old.createCollection('C');
    expect(await old.addToCollection(cid, [vids.single.id]), 1);
  });

  test('playlist append order, duplicates allowed', () async {
    final v = await addVideos(3);
    final pid = await db.createPlaylist('P');
    await db.addToPlaylist(pid, [v[2], v[0]]);
    await db.addToPlaylist(pid, [v[0], v[1]]);
    expect(await playlistVideoIds(pid), [v[2], v[0], v[0], v[1]]);
  });

  test('playlist reorder persists', () async {
    final v = await addVideos(3);
    final pid = await db.createPlaylist('P');
    await db.addToPlaylist(pid, v);
    final items = await (db.select(db.playlistItems)
          ..orderBy([(t) => OrderingTerm.asc(t.position)]))
        .get();
    final ids = [for (final i in items) i.id];
    await db.reorderPlaylist(pid, [ids[2], ids[0], ids[1]]);
    expect(await playlistVideoIds(pid), [v[2], v[0], v[1]]);
    await db.removePlaylistItem(ids[0]);
    expect(await playlistVideoIds(pid), [v[2], v[1]]);
  });

  test('collection add dedupes and a video can be in many collections',
      () async {
    final v = await addVideos(3);
    final a = await db.createCollection('Goa');
    final b = await db.createCollection('Trip');
    expect(await db.addToCollection(a, [v[0], v[1]]), 2);
    expect(await db.addToCollection(a, [v[1], v[2]]), 1);
    expect(await db.addToCollection(b, [v[0]]), 1);
    expect(await db.select(db.collectionVideos).get(), hasLength(4));
  });

  test('deleting playlist/collection leaves videos', () async {
    final v = await addVideos(2);
    final pid = await db.createPlaylist('P');
    final cid = await db.createCollection('C');
    await db.addToPlaylist(pid, v);
    await db.addToCollection(cid, v);
    await db.deletePlaylist(pid);
    await db.deleteCollection(cid);
    expect(await db.select(db.playlistItems).get(), isEmpty);
    expect(await db.select(db.collectionVideos).get(), isEmpty);
    expect(await db.select(db.videos).get(), hasLength(2));
  });

  test('deleting a video row cascades out of playlists and collections',
      () async {
    final v = await addVideos(2);
    final pid = await db.createPlaylist('P');
    final cid = await db.createCollection('C');
    await db.addToPlaylist(pid, v);
    await db.addToCollection(cid, v);
    await (db.delete(db.videos)..where((t) => t.id.equals(v[0]))).go();
    expect(await playlistVideoIds(pid), [v[1]]);
    expect(await db.select(db.collectionVideos).get(), hasLength(1));
  });

  test('rangeSelect works in both directions and clamps', () {
    final ids = [10, 11, 12, 13, 14];
    expect(rangeSelect(ids, 1, 3), {11, 12, 13});
    expect(rangeSelect(ids, 3, 1), {11, 12, 13});
    expect(rangeSelect(ids, 2, 2), {12});
    expect(rangeSelect(ids, 3, 99), {13, 14});
    expect(rangeSelect([], 0, 3), isEmpty);
  });

  test('shuffledCopy keeps each item exactly once', () {
    final items = List.generate(50, (i) => i);
    final s = shuffledCopy(items, Random(7));
    expect(s.length, 50);
    expect(s.toSet(), items.toSet());
    expect(items, List.generate(50, (i) => i));
  });

  test('collection date range label', () {
    expect(collectionDateRange([]), '');
    expect(collectionDateRange([DateTime(2024, 7, 3)]), 'Jul 2024');
    expect(
        collectionDateRange(
            [DateTime(2024, 8, 9), DateTime(2024, 7, 3), DateTime(2024, 7, 20)]),
        'Jul 2024 to Aug 2024');
    expect(
        collectionSubtitle([
          vid(id: 1, recorded: DateTime(2024, 7, 3)),
          vid(id: 2, recorded: DateTime(2024, 8, 9)),
        ]),
        '2 videos · Jul 2024 to Aug 2024');
  });
}
