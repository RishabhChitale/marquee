import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/db/database.dart';
import 'package:marquee/core/library/library_logic.dart';
import 'package:marquee/core/library/scanner.dart';
import 'package:path/path.dart' as p;

Video vid({
  int id = 1,
  DateTime? recorded,
  DateTime? modified,
  int durationMs = 100000,
  int resumeMs = 0,
}) =>
    Video(
      id: id,
      path: '/x/$id.mp4',
      folderId: 1,
      fileName: '$id.mp4',
      title: 't$id',
      sizeBytes: 1,
      fileModifiedAt: modified ?? DateTime(2020),
      recordedAt: recorded,
      durationMs: durationMs,
      width: 0,
      height: 0,
      addedAt: DateTime(2020),
      resumePositionMs: resumeMs,
      playCount: 0,
      missing: false,
    );

void main() {
  late Directory tmp;
  late AppDatabase db;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('marquee_test');
    db = AppDatabase(NativeDatabase.memory());
  });
  tearDown(() async {
    await db.close();
    tmp.deleteSync(recursive: true);
  });

  Future<LibraryFolder> addFolder() async {
    final id = await db.into(db.libraryFolders).insert(
        LibraryFoldersCompanion.insert(path: tmp.path, addedAt: DateTime.now()));
    return (db.select(db.libraryFolders)..where((t) => t.id.equals(id)))
        .getSingle();
  }

  void touch(String rel, [String content = 'x']) {
    final f = File(p.join(tmp.path, rel));
    f.parent.createSync(recursive: true);
    f.writeAsStringSync(content);
  }

  test('extension filter is case-insensitive and skips hidden/._ files', () {
    expect(isVideoFileName('a.MP4'), isTrue);
    expect(isVideoFileName('a.m2ts'), isTrue);
    expect(isVideoFileName('a.txt'), isFalse);
    expect(isVideoFileName('noext'), isFalse);
    expect(isVideoFileName('._a.mp4'), isFalse);
    expect(isVideoFileName('.hidden.mov'), isFalse);

    touch('a.mp4');
    touch('B.MOV');
    touch('notes.txt');
    touch('._a.mp4');
    touch('.hid/c.mp4');
    touch('sub/d.mkv');
    final names = walkVideos(tmp.path).map((f) => p.basename(f.path)).toSet();
    expect(names, {'a.mp4', 'B.MOV', 'd.mkv'});
  });

  test('scan is idempotent', () async {
    touch('a.mp4');
    touch('sub/b.mkv');
    final folder = await addFolder();
    final s = LibraryScanner(db, useIsolate: false);
    expect(await s.scanFolder(folder), 2);
    final first = await db.select(db.videos).get();
    await s.scanFolder(folder);
    final second = await db.select(db.videos).get();
    expect(second.length, 2);
    expect(second.map((v) => v.id).toSet(), first.map((v) => v.id).toSet());
    expect(second.firstWhere((v) => v.fileName == 'a.mp4').title, 'a');
  });

  test('missing flag set when file gone and cleared when restored', () async {
    touch('a.mp4');
    final folder = await addFolder();
    final s = LibraryScanner(db, useIsolate: false);
    await s.scanFolder(folder);
    final path = p.join(tmp.path, 'a.mp4');
    final backup = File(path).readAsStringSync();
    File(path).deleteSync();
    await s.scanFolder(folder);
    var v = (await db.select(db.videos).get()).single;
    expect(v.missing, isTrue);
    touch('a.mp4', backup);
    await s.scanFolder(folder);
    v = (await db.select(db.videos).get()).single;
    expect(v.missing, isFalse);
  });

  test('month grouping and labels', () {
    final vs = [
      vid(id: 1, recorded: DateTime(2024, 7, 14)),
      vid(id: 2, recorded: DateTime(2024, 7, 2)),
      vid(id: 3, recorded: DateTime(2024, 6, 30)),
      vid(id: 4, recorded: null, modified: DateTime(2023, 1, 5)),
    ];
    final groups = groupByMonth(filterAndSort(vs, '', VideoSort.newest));
    expect(groups.map((g) => g.header).toList(), [
      'July 2024 · 2 videos',
      'June 2024 · 1 video',
      'January 2023 · 1 video',
    ]);
    expect(shortDate(DateTime(2024, 7, 12)), '12 Jul 2024');
  });

  test('resume rule: >5 s and <95 %', () {
    expect(resumeStartMs(vid(resumeMs: 4000)), 0);
    expect(resumeStartMs(vid(resumeMs: 5000)), 0);
    expect(resumeStartMs(vid(resumeMs: 5001)), 5001);
    expect(resumeStartMs(vid(resumeMs: 94000)), 94000);
    expect(resumeStartMs(vid(resumeMs: 95000)), 0);
    expect(progressFraction(vid(resumeMs: 0)), isNull);
    expect(progressFraction(vid(resumeMs: 50000)), 0.5);
    expect(progressFraction(vid(resumeMs: 96000)), isNull);
    expect(isFinished(95000, 100000), isTrue);
    expect(isFinished(94999, 100000), isFalse);
  });

  test('creation_time parsing', () {
    expect(parseCreationTime('2024-07-12T10:30:00.000000Z'),
        DateTime.utc(2024, 7, 12, 10, 30));
    expect(parseCreationTime('2024-07-12T10:30:00+02:00'),
        DateTime.utc(2024, 7, 12, 8, 30));
    expect(parseCreationTime('not a date'), isNull);
    expect(parseCreationTime(''), isNull);
    expect(parseCreationTime(null), isNull);
  });

  test('search and sort', () {
    final vs = [
      vid(id: 1, durationMs: 10, recorded: DateTime(2020)),
      vid(id: 2, durationMs: 30, recorded: DateTime(2021)),
    ];
    expect(filterAndSort(vs, 'T2', VideoSort.newest).single.id, 2);
    expect(filterAndSort(vs, '', VideoSort.longest).first.id, 2);
    expect(filterAndSort(vs, '', VideoSort.oldest).first.id, 1);
  });
}
