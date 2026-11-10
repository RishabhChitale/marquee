/// One song heard at one offset in one video.
class SongHit {
  const SongHit(this.offsetMs, this.artist, this.title, this.data);
  final int offsetMs;
  final String artist;
  final String title;

  /// Whatever else the caller wants to keep (album, links...).
  final Object? data;
}

String songKey(String artist, String title) =>
    '${artist.trim().toLowerCase()}\u0000${title.trim().toLowerCase()}';

/// Same song (case-insensitive artist + title) once per video, keeping the
/// earliest offset. Result is ordered by offset.
List<SongHit> dedupeHits(Iterable<SongHit> hits) {
  final best = <String, SongHit>{};
  for (final h in hits) {
    final k = songKey(h.artist, h.title);
    final cur = best[k];
    if (cur == null || h.offsetMs < cur.offsetMs) best[k] = h;
  }
  return best.values.toList()..sort((a, b) => a.offsetMs.compareTo(b.offsetMs));
}
