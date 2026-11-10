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

class Playlists extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  DateTimeColumn get createdAt => dateTime()();
  DateTimeColumn get updatedAt => dateTime()();
}

@TableIndex(name: 'playlist_items_pos', columns: {#playlistId, #position})
class PlaylistItems extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get playlistId =>
      integer().references(Playlists, #id, onDelete: KeyAction.cascade)();
  IntColumn get videoId =>
      integer().references(Videos, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
}

class Collections extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name =>
      text().customConstraint('NOT NULL UNIQUE COLLATE NOCASE')();
  DateTimeColumn get createdAt => dateTime()();
  IntColumn get coverVideoId => integer()
      .nullable()
      .references(Videos, #id, onDelete: KeyAction.setNull)();
}

class CollectionVideos extends Table {
  IntColumn get collectionId =>
      integer().references(Collections, #id, onDelete: KeyAction.cascade)();
  IntColumn get videoId =>
      integer().references(Videos, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get addedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {collectionId, videoId};
}

@DriftDatabase(
    tables: [
      LibraryFolders,
      Videos,
      Playlists,
      PlaylistItems,
      Collections,
      CollectionVideos,
    ])
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.createTable(playlists);
            await m.createTable(playlistItems);
            await m.createIndex(playlistItemsPos);
            await m.createTable(collections);
            await m.createTable(collectionVideos);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  Stream<List<Video>> watchVideos() => select(videos).watch();
  Stream<List<LibraryFolder>> watchFolders() => select(libraryFolders).watch();

  // ---------------------------------------------------------------- playlists

  Future<int> createPlaylist(String name) {
    final now = DateTime.now();
    return into(playlists).insert(PlaylistsCompanion.insert(
        name: name.trim(), createdAt: now, updatedAt: now));
  }

  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((t) => t.id.equals(id))).write(
          PlaylistsCompanion(
              name: Value(name.trim()), updatedAt: Value(DateTime.now())));

  /// Deletes the playlist and its items only; videos are untouched.
  Future<void> deletePlaylist(int id) =>
      (delete(playlists)..where((t) => t.id.equals(id))).go();

  Future<List<PlaylistItem>> _itemsOf(int playlistId) =>
      (select(playlistItems)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Future<void> _touchPlaylist(int id) =>
      (update(playlists)..where((t) => t.id.equals(id)))
          .write(PlaylistsCompanion(updatedAt: Value(DateTime.now())));

  /// Appends [videoIds] to the end, in the given order. Duplicates allowed.
  Future<void> addToPlaylist(int playlistId, List<int> videoIds) =>
      transaction(() async {
        final existing = await _itemsOf(playlistId);
        var pos = existing.isEmpty ? 0 : existing.last.position + 1;
        for (final v in videoIds) {
          await into(playlistItems).insert(PlaylistItemsCompanion.insert(
              playlistId: playlistId, videoId: v, position: pos++));
        }
        await _touchPlaylist(playlistId);
      });

  /// Removes one row (by item id) and closes the gap in positions.
  Future<void> removePlaylistItem(int itemId) => transaction(() async {
        final item = await (select(playlistItems)
              ..where((t) => t.id.equals(itemId)))
            .getSingleOrNull();
        if (item == null) return;
        await (delete(playlistItems)..where((t) => t.id.equals(itemId))).go();
        final rest = await _itemsOf(item.playlistId);
        for (var i = 0; i < rest.length; i++) {
          if (rest[i].position != i) {
            await (update(playlistItems)..where((t) => t.id.equals(rest[i].id)))
                .write(PlaylistItemsCompanion(position: Value(i)));
          }
        }
        await _touchPlaylist(item.playlistId);
      });

  /// Persists a new order: [orderedItemIds] are playlist_items ids.
  Future<void> reorderPlaylist(int playlistId, List<int> orderedItemIds) =>
      transaction(() async {
        for (var i = 0; i < orderedItemIds.length; i++) {
          await (update(playlistItems)
                ..where((t) =>
                    t.id.equals(orderedItemIds[i]) &
                    t.playlistId.equals(playlistId)))
              .write(PlaylistItemsCompanion(position: Value(i)));
        }
        await _touchPlaylist(playlistId);
      });

  // -------------------------------------------------------------- collections

  Future<Collection?> _collectionNamed(String name, {int? except}) async {
    final n = name.trim().toLowerCase();
    final all = await select(collections).get();
    for (final c in all) {
      if (c.id != except && c.name.toLowerCase() == n) return c;
    }
    return null;
  }

  /// Creates a collection, or returns the id of the existing one with the
  /// same name (case-insensitive).
  Future<int> createCollection(String name) async {
    final existing = await _collectionNamed(name);
    if (existing != null) return existing.id;
    return into(collections).insert(CollectionsCompanion.insert(
        name: name.trim(), createdAt: DateTime.now()));
  }

  /// False when another collection already uses [name].
  Future<bool> renameCollection(int id, String name) async {
    if (await _collectionNamed(name, except: id) != null) return false;
    await (update(collections)..where((t) => t.id.equals(id)))
        .write(CollectionsCompanion(name: Value(name.trim())));
    return true;
  }

  /// Deletes the collection and its membership rows only.
  Future<void> deleteCollection(int id) =>
      (delete(collections)..where((t) => t.id.equals(id))).go();

  /// Adds videos not already present; returns how many were actually added.
  Future<int> addToCollection(int collectionId, List<int> videoIds) =>
      transaction(() async {
        final have = (await (select(collectionVideos)
                  ..where((t) => t.collectionId.equals(collectionId)))
                .get())
            .map((r) => r.videoId)
            .toSet();
        var added = 0;
        final now = DateTime.now();
        for (final v in videoIds) {
          if (!have.add(v)) continue;
          await into(collectionVideos).insert(CollectionVideosCompanion.insert(
              collectionId: collectionId, videoId: v, addedAt: now));
          added++;
        }
        return added;
      });

  Future<void> removeFromCollection(int collectionId, List<int> videoIds) =>
      transaction(() async {
        await (delete(collectionVideos)
              ..where((t) =>
                  t.collectionId.equals(collectionId) &
                  t.videoId.isIn(videoIds)))
            .go();
        await (update(collections)
              ..where((t) =>
                  t.id.equals(collectionId) & t.coverVideoId.isIn(videoIds)))
            .write(const CollectionsCompanion(coverVideoId: Value(null)));
      });

  Future<void> setCollectionCover(int collectionId, int? videoId) =>
      (update(collections)..where((t) => t.id.equals(collectionId)))
          .write(CollectionsCompanion(coverVideoId: Value(videoId)));
}
