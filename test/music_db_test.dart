import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/db/database.dart';
import 'package:marquee/core/library/tags_logic.dart';

MusicMatch _mm(int video, String artist, String title) => MusicMatch(
  id: 0,
  videoId: video,
  offsetMs: 0,
  artist: artist,
  title: title,
  matchedAt: DateTime(2026),
);

Video _v(int id, {String? genre}) => Video(
  id: id,
  path: '/x/$id.mp4',
  folderId: 1,
  fileName: '$id.mp4',
  title: '$id',
  sizeBytes: 1,
  fileModifiedAt: DateTime(2026),
  durationMs: 60000,
  width: 0,
  height: 0,
  addedAt: DateTime(2026),
  resumePositionMs: 0,
  playCount: 0,
  missing: false,
  genre: genre,
  peopleOverridden: false,
  titleOverridden: false,
  sourceChecked: false,
  musicScanFailed: false,
);

void main() {
  test('v3 to v4 migration keeps rows and adds music tables', () async {
    final old = AppDatabase(
      NativeDatabase.memory(
        setup: (raw) {
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
        missing INTEGER NOT NULL DEFAULT 0 CHECK (missing IN (0, 1)),
        genre TEXT, source_url TEXT, source_domain TEXT,
        people_overridden INTEGER NOT NULL DEFAULT 0,
        title_overridden INTEGER NOT NULL DEFAULT 0,
        source_checked INTEGER NOT NULL DEFAULT 0)''');
          raw.execute(
            "INSERT INTO library_folders (path, added_at) VALUES ('/x', 0)",
          );
          raw.execute('''INSERT INTO videos (path, folder_id, file_name, title,
        size_bytes, file_modified_at, added_at)
        VALUES ('/x/a.mp4', 1, 'a.mp4', 'a', 1, 0, 0)''');
          raw.execute('PRAGMA user_version = 3');
        },
      ),
    );
    addTearDown(old.close);
    final vids = await old.select(old.videos).get();
    expect(vids.single.title, 'a');
    expect(vids.single.musicScannedAt, isNull);
    expect(vids.single.musicScanFailed, isFalse);
    expect(await old.select(old.musicMatches).get(), isEmpty);
    await old
        .into(old.musicMatches)
        .insert(
          MusicMatchesCompanion.insert(
            videoId: 1,
            offsetMs: 5000,
            artist: 'A',
            title: 'T',
            matchedAt: DateTime(2026),
          ),
        );
    expect((await old.select(old.musicMatches).get()).single.title, 'T');
  });

  group('music tags', () {
    final a = _v(1, genre: 'Travel');
    final b = _v(2);
    final c = _v(3);
    final all = [a, b, c];
    final idx = buildMusicIndex([
      _mm(1, 'Daft Punk', 'Get Lucky'),
      _mm(2, 'daft punk', 'get lucky '),
      _mm(2, 'Other', 'Song'),
    ]);

    test('index merges case-insensitively', () {
      expect(idx[2]!.length, 2);
      expect(idx[1]!.keys.single, idx[2]!.keys.first);
    });

    test('counts and filter', () {
      final counts = musicCounts(all, const {}, idx, null, null);
      expect(counts.first.count, 2);
      final key = counts.first.key;
      final got = applyTagFilter(
        all,
        const {},
        TagFilter(musicKey: key),
        music: idx,
      );
      expect(got.map((v) => v.id), [1, 2]);
    });

    test('ANDed with genre', () {
      final key = musicCounts(all, const {}, idx, null, null).first.key;
      final got = applyTagFilter(
        all,
        const {},
        TagFilter(genre: 'Travel', musicKey: key),
        music: idx,
      );
      expect(got.map((v) => v.id), [1]);
      expect(
        musicCounts(all, const {}, idx, 'Travel', null).first.count,
        1,
      );
    });
  });
}
