import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/db/database.dart';
import 'package:marquee/core/library/name_parser.dart';
import 'package:marquee/core/library/scanner.dart';
import 'package:marquee/core/library/source_detector.dart';
import 'package:marquee/core/library/tags_logic.dart';
import 'package:path/path.dart' as p;

void main() {
  group('parseName', () {
    test('creator and featured', () {
      final r = parseName('Beach day (Mom, Dad & Nani)');
      expect(r.title, 'Beach day');
      expect(r.creator, 'Mom');
      expect(r.featured, ['Dad', 'Nani']);
    });
    test('single name is creator', () {
      final r = parseName('Beach day (Mom)');
      expect(r.creator, 'Mom');
      expect(r.featured, isEmpty);
    });
    test('ignores year, resolution, copy, final groups', () {
      for (final g in ['2019', '1080p', 'copy', 'final', '2']) {
        final r = parseName('Clip ($g)');
        expect(r.creator, isNull, reason: g);
        expect(r.title, 'Clip ($g)', reason: g);
      }
    });
    test('last meaningful group wins; dedupes case-insensitively', () {
      final r = parseName('Trip (Old) (Riya, riya, Dad)');
      expect(r.creator, 'Riya');
      expect(r.featured, ['Dad']);
    });
    test('featuring separators', () {
      final r = parseName('x (Riya feat. Dad and Nani)');
      expect(r.creator, 'Riya');
      expect(r.featured, ['Dad', 'Nani']);
    });
    test('no group', () {
      final r = parseName('Plain name');
      expect(r.title, 'Plain name');
      expect(r.creator, isNull);
    });
  });

  group('deriveGenre', () {
    test('first subfolder', () {
      expect(deriveGenre('/v/Trips/2020/a.mp4', '/v'), 'Trips');
    });
    test('file directly in folder', () {
      expect(deriveGenre('/v/a.mp4', '/v'), isNull);
    });
    test('windows paths', () {
      expect(
        deriveGenre(r'D:\Videos\Birthdays\a.mp4', r'D:\Videos'),
        'Birthdays',
      );
    });
  });

  group('source detection', () {
    test('domainOf strips www', () {
      expect(domainOf('https://www.example.com/x'), 'example.com');
    });
    test('pickSource prefers non-CDN', () {
      final s = pickSource([
        'https://rr1.googlevideo.com/a',
        'https://www.example.org/watch?v=1',
      ]);
      expect(s!.domain, 'example.org');
    });
    test('pickSource falls back to CDN', () {
      expect(pickSource(['https://x.fbcdn.net/a'])!.domain, 'x.fbcdn.net');
      expect(pickSource([]), isNull);
    });
    test('parseWhereFromsJson', () {
      expect(parseWhereFromsJson('["https://a.com/v","https://b.com/"]'), [
        'https://a.com/v',
        'https://b.com/',
      ]);
      expect(parseWhereFromsJson('garbage'), isEmpty);
    });
    test('parseZoneIdentifier prefers referrer', () {
      final l = parseZoneIdentifier(
        '[ZoneTransfer]\r\nZoneId=3\r\nHostUrl=https://h.com/f\r\nReferrerUrl=https://r.com/p\r\n',
      );
      expect(l, ['https://r.com/p', 'https://h.com/f']);
    });
  });

  group('tag filters', () {
    Video v(int id, String? genre) => Video(
      id: id,
      path: '/x/$id.mp4',
      folderId: 1,
      fileName: '$id.mp4',
      title: 't$id',
      sizeBytes: 1,
      fileModifiedAt: DateTime(2020),
      durationMs: 0,
      width: 0,
      height: 0,
      addedAt: DateTime(2020),
      resumePositionMs: 0,
      playCount: 0,
      missing: false,
      genre: genre,
      peopleOverridden: false,
      titleOverridden: false,
      sourceChecked: false,
    );
    final all = [v(1, 'Trips'), v(2, 'Trips'), v(3, 'Parties')];
    final idx = <int, List<PersonRef>>{
      1: [const PersonRef('Mom', 'mom', true)],
      2: [
        const PersonRef('Dad', 'dad', true),
        const PersonRef('Mom', 'mom', false),
      ],
      3: [const PersonRef('Mom', 'mom', true)],
    };
    test('AND filter', () {
      final r = applyTagFilter(
        all,
        idx,
        const TagFilter(genre: 'Trips', personKey: 'mom'),
      );
      expect(r.map((e) => e.id), [1, 2]);
      expect(
        applyTagFilter(
          all,
          idx,
          const TagFilter(genre: 'Parties', personKey: 'dad'),
        ),
        isEmpty,
      );
    });
    test('counts reflect other row', () {
      expect(genreCounts(all, idx, 'dad').map((c) => '${c.label}:${c.count}'), [
        'Trips:1',
      ]);
      final pc = personCounts(all, idx, 'Trips');
      expect(pc.first.label, 'Mom');
      expect(pc.first.count, 2);
    });
    test('peopleLine', () {
      expect(peopleLine(idx[2]), 'by Dad · ft. Mom');
      expect(peopleLine(null), isNull);
    });
  });

  group('scanner organizing', () {
    late Directory tmp;
    late AppDatabase db;
    setUp(() {
      tmp = Directory.systemTemp.createTempSync('marquee_org');
      db = AppDatabase(NativeDatabase.memory());
    });
    tearDown(() async {
      await db.close();
      tmp.deleteSync(recursive: true);
    });
    void touch(String rel) {
      final f = File(p.join(tmp.path, rel));
      f.parent.createSync(recursive: true);
      f.writeAsStringSync('x');
    }

    Future<LibraryFolder> folder() async {
      final id = await db
          .into(db.libraryFolders)
          .insert(
            LibraryFoldersCompanion.insert(
              path: tmp.path,
              addedAt: DateTime.now(),
            ),
          );
      return (db.select(
        db.libraryFolders,
      )..where((t) => t.id.equals(id))).getSingle();
    }

    test('genre and people derived; override survives rescan', () async {
      touch('Trips/Beach day (Mom, Dad).mp4');
      final f = await folder();
      final s = LibraryScanner(db, useIsolate: false);
      await s.scanFolder(f);
      var v = (await db.select(db.videos).get()).single;
      expect(v.title, 'Beach day');
      expect(v.genre, 'Trips');
      final people = await db.select(db.people).get();
      expect(people.map((e) => e.name).toSet(), {'Mom', 'Dad'});

      await db.overridePeople(v.id, 'Nani', ['Riya']);
      await s.scanFolder(f);
      v = (await db.select(db.videos).get()).single;
      expect(v.peopleOverridden, isTrue);
      final links = await db.select(db.videoPeople).get();
      final names = {
        for (final x in await db.select(db.people).get()) x.id: x.name,
      };
      expect(links.map((l) => names[l.personId]).toSet(), {'Nani', 'Riya'});
    });

    test('renamed title is not replaced by rescans', () async {
      touch('Beach day (Mom).mp4');
      final f = await folder();
      final s = LibraryScanner(db, useIsolate: false);
      await s.scanFolder(f);
      final v = (await db.select(db.videos).get()).single;
      await (db.update(db.videos)..where((t) => t.id.equals(v.id))).write(
        const VideosCompanion(
          title: Value('My title'),
          titleOverridden: Value(true),
        ),
      );
      await s.scanFolder(f);
      expect((await db.select(db.videos).get()).single.title, 'My title');
    });
  });

  test('v2 to v3 migration keeps rows', () async {
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
        missing INTEGER NOT NULL DEFAULT 0 CHECK (missing IN (0, 1)))''');
          raw.execute(
            "INSERT INTO library_folders (path, added_at) VALUES ('/x', 0)",
          );
          raw.execute('''INSERT INTO videos (path, folder_id, file_name, title,
        size_bytes, file_modified_at, added_at)
        VALUES ('/x/a.mp4', 1, 'a.mp4', 'a', 1, 0, 0)''');
          raw.execute('PRAGMA user_version = 2');
        },
      ),
    );
    addTearDown(old.close);
    final vids = await old.select(old.videos).get();
    expect(vids.single.title, 'a');
    expect(vids.single.genre, isNull);
    expect(vids.single.sourceChecked, isFalse);
    expect(await old.select(old.people).get(), isEmpty);
  });
}
