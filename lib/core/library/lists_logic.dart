import 'dart:math';

import '../db/database.dart';
import 'library_logic.dart';

/// Ids from [anchorIndex] to [targetIndex] inclusive (either direction) in the
/// visible order [orderedIds]. Out-of-range indexes are clamped.
Set<int> rangeSelect(List<int> orderedIds, int anchorIndex, int targetIndex) {
  if (orderedIds.isEmpty) return {};
  final a = anchorIndex.clamp(0, orderedIds.length - 1);
  final b = targetIndex.clamp(0, orderedIds.length - 1);
  final lo = min(a, b), hi = max(a, b);
  return orderedIds.sublist(lo, hi + 1).toSet();
}

/// Fisher-Yates copy: every element appears exactly once.
List<T> shuffledCopy<T>(List<T> items, [Random? random]) {
  final r = random ?? Random();
  final out = List<T>.of(items);
  for (var i = out.length - 1; i > 0; i--) {
    final j = r.nextInt(i + 1);
    final t = out[i];
    out[i] = out[j];
    out[j] = t;
  }
  return out;
}

const _short = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec',
];

String _monthYear(DateTime d) => '${_short[d.month - 1]} ${d.year}';

/// "Jul 2024 to Aug 2024", or "Jul 2024" when everything is in one month,
/// or '' for no dates.
String collectionDateRange(Iterable<DateTime> dates) {
  DateTime? lo, hi;
  for (final d in dates) {
    if (lo == null || d.isBefore(lo)) lo = d;
    if (hi == null || d.isAfter(hi)) hi = d;
  }
  if (lo == null || hi == null) return '';
  final a = _monthYear(lo), b = _monthYear(hi);
  return a == b ? a : '$a to $b';
}

String videoCountLabel(int n) => '$n video${n == 1 ? '' : 's'}';

/// "14 videos · Jul 2024 to Aug 2024".
String collectionSubtitle(List<Video> videos) {
  final range =
      collectionDateRange(videos.map((v) => effectiveDate(v).toLocal()));
  return range.isEmpty
      ? videoCountLabel(videos.length)
      : '${videoCountLabel(videos.length)} · $range';
}

/// Snackbar text after an add. [added] of [requested] actually went in.
String addedMessage(int added, int requested, String listName) {
  if (added == 0) {
    return requested == 1
        ? 'Already in $listName'
        : 'All $requested videos are already in $listName';
  }
  final skipped = requested - added;
  return 'Added ${videoCountLabel(added)} to $listName'
      '${skipped > 0 ? ' ($skipped already in it)' : ''}';
}

class PlaylistEntry {
  const PlaylistEntry(this.item, this.video);
  final PlaylistItem item;
  final Video video;
}

class PlaylistSummary {
  PlaylistSummary(this.playlist, this.entries);
  final Playlist playlist;
  final List<PlaylistEntry> entries;
  int get count => entries.length;
  int get totalMs => entries.fold(0, (a, e) => a + e.video.durationMs);
  Video? get first => entries.isEmpty ? null : entries.first.video;
}

class CollectionSummary {
  CollectionSummary(this.collection, this.videos, this.updatedAt);
  final Collection collection;
  final List<Video> videos;
  final DateTime updatedAt;

  /// The chosen cover, else the most recent video.
  Video? get cover {
    final id = collection.coverVideoId;
    if (id != null) {
      for (final v in videos) {
        if (v.id == id) return v;
      }
    }
    if (videos.isEmpty) return null;
    return videos.reduce(
        (a, b) => effectiveDate(a).isAfter(effectiveDate(b)) ? a : b);
  }
}

List<PlaylistSummary> buildPlaylistSummaries(List<Playlist> playlists,
    List<PlaylistItem> items, List<Video> videos) {
  final byId = {for (final v in videos) v.id: v};
  final byList = <int, List<PlaylistEntry>>{};
  for (final it in items) {
    final v = byId[it.videoId];
    if (v == null) continue;
    (byList[it.playlistId] ??= []).add(PlaylistEntry(it, v));
  }
  for (final l in byList.values) {
    l.sort((a, b) => a.item.position.compareTo(b.item.position));
  }
  final out = [
    for (final p in playlists) PlaylistSummary(p, byList[p.id] ?? const [])
  ]..sort((a, b) => b.playlist.updatedAt.compareTo(a.playlist.updatedAt));
  return out;
}

List<CollectionSummary> buildCollectionSummaries(List<Collection> collections,
    List<CollectionVideo> links, List<Video> videos) {
  final byId = {for (final v in videos) v.id: v};
  final vids = <int, List<Video>>{};
  final updated = <int, DateTime>{};
  for (final l in links) {
    final v = byId[l.videoId];
    if (v == null) continue;
    (vids[l.collectionId] ??= []).add(v);
    final u = updated[l.collectionId];
    if (u == null || l.addedAt.isAfter(u)) updated[l.collectionId] = l.addedAt;
  }
  final out = [
    for (final c in collections)
      CollectionSummary(c, vids[c.id] ?? const [], () {
        final u = updated[c.id];
        return u != null && u.isAfter(c.createdAt) ? u : c.createdAt;
      }())
  ]..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  return out;
}

/// "Goa trip, Grandma +1" chip data: up to [max] names plus overflow count.
({List<Collection> shown, int extra}) chipSplit(List<Collection> cs,
    {int max = 2}) {
  final sorted = List<Collection>.of(cs)
    ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  return (
    shown: sorted.take(max).toList(),
    extra: sorted.length > max ? sorted.length - max : 0
  );
}
