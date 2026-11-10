import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'database.g.dart';

class LibraryFolders extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  DateTimeColumn get addedAt => dateTime()();
}

@TableIndex(name: 'videos_recorded_at', columns: {#recordedAt})
class Videos extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get path => text().unique()();
  IntColumn get folderId =>
      integer().references(LibraryFolders, #id, onDelete: KeyAction.cascade)();
  TextColumn get fileName => text()();
  TextColumn get title => text()();
  IntColumn get sizeBytes => integer()();
  DateTimeColumn get fileModifiedAt => dateTime()();
  DateTimeColumn get recordedAt => dateTime().nullable()();
  IntColumn get durationMs => integer().withDefault(const Constant(0))();
  IntColumn get width => integer().withDefault(const Constant(0))();
  IntColumn get height => integer().withDefault(const Constant(0))();
  TextColumn get thumbnailPath => text().nullable()();
  DateTimeColumn get addedAt => dateTime()();
  DateTimeColumn get lastPlayedAt => dateTime().nullable()();
  IntColumn get resumePositionMs => integer().withDefault(const Constant(0))();
  IntColumn get playCount => integer().withDefault(const Constant(0))();
  BoolColumn get missing => boolean().withDefault(const Constant(false))();
}

@DriftDatabase(tables: [LibraryFolders, Videos])
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens `marquee.db` in the application support directory.
  factory AppDatabase.open() => AppDatabase(LazyDatabase(() async {
        final dir = await getApplicationSupportDirectory();
        await dir.create(recursive: true);
        return NativeDatabase.createInBackground(
            File(p.join(dir.path, 'marquee.db')));
      }));

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Video>> watchVideos() => select(videos).watch();
  Stream<List<LibraryFolder>> watchFolders() => select(libraryFolders).watch();
}
