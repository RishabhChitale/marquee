import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../db/database.dart';
import 'library_providers.dart';
import 'lists_logic.dart';

final _playlistsRaw = StreamProvider<List<Playlist>>(
    (ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.playlists).watch();
});
final _playlistItemsRaw = StreamProvider<List<PlaylistItem>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.playlistItems).watch();
});
final _collectionsRaw = StreamProvider<List<Collection>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.collections).watch();
});
final _collectionVideosRaw = StreamProvider<List<CollectionVideo>>((ref) {
  final db = ref.watch(databaseProvider);
  return db.select(db.collectionVideos).watch();
});

/// Playlists with their ordered entries, most recently updated first.
final playlistSummariesProvider = Provider<List<PlaylistSummary>>((ref) {
  return buildPlaylistSummaries(
    ref.watch(_playlistsRaw).value ?? const [],
    ref.watch(_playlistItemsRaw).value ?? const [],
    ref.watch(videosProvider).value ?? const [],
  );
});

/// Collections with their videos, most recently updated first.
final collectionSummariesProvider = Provider<List<CollectionSummary>>((ref) {
  return buildCollectionSummaries(
    ref.watch(_collectionsRaw).value ?? const [],
    ref.watch(_collectionVideosRaw).value ?? const [],
    ref.watch(videosProvider).value ?? const [],
  );
});

/// video id -> collections it belongs to (for the card chips).
final videoCollectionsProvider = Provider<Map<int, List<Collection>>>((ref) {
  final out = <int, List<Collection>>{};
  for (final s in ref.watch(collectionSummariesProvider)) {
    for (final v in s.videos) {
      (out[v.id] ??= []).add(s.collection);
    }
  }
  return out;
});
