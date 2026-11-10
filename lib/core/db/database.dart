import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../library/name_parser.dart';

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
  TextColumn get genre => text().nullable()();
  TextColumn get sourceUrl => text().nullable()();
  TextColumn get sourceDomain => text().nullable()();
  BoolColumn get peopleOverridden =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get titleOverridden =>
      boolean().withDefault(const Constant(false))();
  BoolColumn get sourceChecked =>
      boolean().withDefault(const Constant(false))();
  DateTimeColumn get musicScannedAt => dateTime().nullable()();
  BoolColumn get musicScanFailed =>
      boolean().withDefault(const Constant(false))();
}

@DataClassName('MusicMatch')
class MusicMatches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get videoId =>
      integer().references(Videos, #id, onDelete: KeyAction.cascade)();
  IntColumn get offsetMs => integer()();
  TextColumn get artist => text()();
  TextColumn get title => text()();
  TextColumn get album => text().nullable()();
  TextColumn get releaseDate => text().nullable()();
  TextColumn get songLink => text().nullable()();
  TextColumn get spotifyUrl => text().nullable()();
  TextColumn get appleMusicUrl => text().nullable()();
  DateTimeColumn get matchedAt => dateTime()();
}

class People extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get name => text()();
  TextColumn get nameKey => text().unique()();
}

class VideoPeople extends Table {
  IntColumn get videoId =>
      integer().references(Videos, #id, onDelete: KeyAction.cascade)();
  IntColumn get personId =>
      integer().references(People, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text().customConstraint(
    "NOT NULL CHECK (role IN ('creator', 'featured'))",
  )();

  @override
  Set<Column> get primaryKey => {videoId, personId};
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
  IntColumn get coverVideoId => integer().nullable().references(
    Videos,
    #id,
    onDelete: KeyAction.setNull,
  )();
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
    People,
    VideoPeople,
    MusicMatches,
  ],
)
class AppDatabase extends _$AppDatabase {
  AppDatabase(super.e);

  /// Opens `marquee.db` in the application support directory.
  factory AppDatabase.open() => AppDatabase(
    LazyDatabase(() async {
      final dir = await getApplicationSupportDirectory();
      await dir.create(recursive: true);
      return NativeDatabase.createInBackground(
        File(p.join(dir.path, 'marquee.db')),
      );
    }),
  );

  @override
  int get schemaVersion => 4;

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
      if (from < 3) {
        await m.addColumn(videos, videos.genre);
        await m.addColumn(videos, videos.sourceUrl);
        await m.addColumn(videos, videos.sourceDomain);
        await m.addColumn(videos, videos.peopleOverridden);
        await m.addColumn(videos, videos.titleOverridden);
        await m.addColumn(videos, videos.sourceChecked);
        await m.createTable(people);
        await m.createTable(videoPeople);
      }
      if (from < 4) {
        await m.addColumn(videos, videos.musicScannedAt);
        await m.addColumn(videos, videos.musicScanFailed);
        await m.createTable(musicMatches);
      }
    },
    beforeOpen: (details) async {
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );

  Stream<List<Video>> watchVideos() => select(videos).watch();
  Stream<List<VideoPeopleData>> watchVideoPeople() =>
      select(videoPeople).watch();
  Stream<List<PeopleData>> watchPeople() => select(people).watch();
  Stream<List<MusicMatch>> watchMusicMatches() => select(musicMatches).watch();

  /// Replaces all music matches of one video with [matches] (already
  /// de-duplicated) and stamps the scan result. Never touches the file.
  Future<void> saveMusicResult(
    int videoId,
    List<MusicMatchesCompanion> matches, {
    required bool failed,
  }) => transaction(() async {
    await (delete(musicMatches)..where((t) => t.videoId.equals(videoId))).go();
    for (final m in matches) {
      await into(musicMatches).insert(m);
    }
    await (update(videos)..where((t) => t.id.equals(videoId))).write(
      VideosCompanion(
        musicScannedAt: Value(DateTime.now()),
        musicScanFailed: Value(failed),
      ),
    );
  });

  /// Replaces the people of one video (creator first, then featured).
  /// Names are de-duplicated by case-insensitive key; the first spelling seen
  /// for a key is kept as the display name.
  Future<void> setVideoPeople(
    int videoId,
    String? creator,
    List<String> featured,
  ) async {
    await transaction(() async {
      await (delete(videoPeople)..where((t) => t.videoId.equals(videoId))).go();
      final seen = <String>{};
      Future<void> add(String name, String role) async {
        final key = personKey(name);
        if (key.isEmpty || !seen.add(key)) return;
        await into(people).insert(
          PeopleCompanion.insert(
            name: name.trim().replaceAll(RegExp(r'\s+'), ' '),
            nameKey: key,
          ),
          mode: InsertMode.insertOrIgnore,
        );
        final row = await (select(
          people,
        )..where((t) => t.nameKey.equals(key))).getSingle();
        await into(videoPeople).insert(
          VideoPeopleCompanion.insert(
            videoId: videoId,
            personId: row.id,
            role: role,
          ),
        );
      }

      if (creator != null) await add(creator, 'creator');
      for (final f in featured) {
        await add(f, 'featured');
      }
    });
  }

  /// Manual override: stores the people and protects them from rescans.
  Future<void> overridePeople(
    int videoId,
    String? creator,
    List<String> featured,
  ) async {
    await setVideoPeople(videoId, creator, featured);
    await (update(videos)..where((t) => t.id.equals(videoId))).write(
      const VideosCompanion(peopleOverridden: Value(true)),
    );
  }

  Future<void> setSource(int videoId, String? url, String? domain) =>
      (update(videos)..where((t) => t.id.equals(videoId))).write(
        VideosCompanion(
          sourceUrl: Value(url),
          sourceDomain: Value(domain),
          sourceChecked: const Value(true),
        ),
      );

  Stream<List<LibraryFolder>> watchFolders() => select(libraryFolders).watch();

  // ---------------------------------------------------------------- playlists

  Future<int> createPlaylist(String name) {
    final now = DateTime.now();
    return into(playlists).insert(
      PlaylistsCompanion.insert(
        name: name.trim(),
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  Future<void> renamePlaylist(int id, String name) =>
      (update(playlists)..where((t) => t.id.equals(id))).write(
        PlaylistsCompanion(
          name: Value(name.trim()),
          updatedAt: Value(DateTime.now()),
        ),
      );

  /// Deletes the playlist and its items only; videos are untouched.
  Future<void> deletePlaylist(int id) =>
      (delete(playlists)..where((t) => t.id.equals(id))).go();

  Future<List<PlaylistItem>> _itemsOf(int playlistId) =>
      (select(playlistItems)
            ..where((t) => t.playlistId.equals(playlistId))
            ..orderBy([(t) => OrderingTerm.asc(t.position)]))
          .get();

  Future<void> _touchPlaylist(int id) =>
      (update(playlists)..where((t) => t.id.equals(id))).write(
        PlaylistsCompanion(updatedAt: Value(DateTime.now())),
      );

  /// Appends [videoIds] to the end, in the given order. Duplicates allowed.
  Future<void> addToPlaylist(int playlistId, List<int> videoIds) =>
      transaction(() async {
        final existing = await _itemsOf(playlistId);
        var pos = existing.isEmpty ? 0 : existing.last.position + 1;
        for (final v in videoIds) {
          await into(playlistItems).insert(
            PlaylistItemsCompanion.insert(
              playlistId: playlistId,
              videoId: v,
              position: pos++,
            ),
          );
        }
        await _touchPlaylist(playlistId);
      });

  /// Removes one row (by item id) and closes the gap in positions.
  Future<void> removePlaylistItem(int itemId) => transaction(() async {
    final item = await (select(
      playlistItems,
    )..where((t) => t.id.equals(itemId))).getSingleOrNull();
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
          await (update(playlistItems)..where(
                (t) =>
                    t.id.equals(orderedItemIds[i]) &
                    t.playlistId.equals(playlistId),
              ))
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
    return into(collections).insert(
      CollectionsCompanion.insert(name: name.trim(), createdAt: DateTime.now()),
    );
  }

  /// False when another collection already uses [name].
  Future<bool> renameCollection(int id, String name) async {
    if (await _collectionNamed(name, except: id) != null) return false;
    await (update(collections)..where((t) => t.id.equals(id))).write(
      CollectionsCompanion(name: Value(name.trim())),
    );
    return true;
  }

  /// Deletes the collection and its membership rows only.
  Future<void> deleteCollection(int id) =>
      (delete(collections)..where((t) => t.id.equals(id))).go();

  /// Adds videos not already present; returns how many were actually added.
  Future<int> addToCollection(int collectionId, List<int> videoIds) =>
      transaction(() async {
        final have =
            (await (select(
                  collectionVideos,
                )..where((t) => t.collectionId.equals(collectionId))).get())
                .map((r) => r.videoId)
                .toSet();
        var added = 0;
        final now = DateTime.now();
        for (final v in videoIds) {
          if (!have.add(v)) continue;
          await into(collectionVideos).insert(
            CollectionVideosCompanion.insert(
              collectionId: collectionId,
              videoId: v,
              addedAt: now,
            ),
          );
          added++;
        }
        return added;
      });

  Future<void> removeFromCollection(int collectionId, List<int> videoIds) =>
      transaction(() async {
        await (delete(collectionVideos)..where(
              (t) =>
                  t.collectionId.equals(collectionId) &
                  t.videoId.isIn(videoIds),
            ))
            .go();
        await (update(collections)..where(
              (t) => t.id.equals(collectionId) & t.coverVideoId.isIn(videoIds),
            ))
            .write(const CollectionsCompanion(coverVideoId: Value(null)));
      });

  Future<void> setCollectionCover(int collectionId, int? videoId) =>
      (update(collections)..where((t) => t.id.equals(collectionId))).write(
        CollectionsCompanion(coverVideoId: Value(videoId)),
      );
}
