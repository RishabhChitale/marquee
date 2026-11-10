import 'package:path/path.dart' as p;

import '../db/database.dart';

const videoExtensions = {
  'mp4', 'm4v', 'mov', 'mkv', 'avi', 'wmv', 'mts', 'm2ts', '3gp', 'webm',
  'mpg', 'mpeg',
};

/// True for a video file we should index (case-insensitive extension, not
/// hidden, not a macOS `._` resource-fork file).
bool isVideoFileName(String name) {
  if (name.startsWith('.')) return false;
  final ext = p.extension(name).toLowerCase();
  if (ext.isEmpty) return false;
  return videoExtensions.contains(ext.substring(1));
}

/// Parses a container creation_time tag. ISO-8601 with `Z` or an offset is
/// converted to UTC; garbage returns null.
DateTime? parseCreationTime(String? raw) {
  if (raw == null) return null;
  final s = raw.trim();
  if (s.isEmpty) return null;
  final dt = DateTime.tryParse(s);
  if (dt == null) return null;
  // Reject epoch-zero style placeholders written by some cameras.
  if (dt.year < 1971) return null;
  return dt.toUtc();
}

/// Position to resume at: only if more than 5 s in and under 95 % played.
int resumeStartMs(Video v) {
  final pos = v.resumePositionMs;
  if (pos <= 5000) return 0;
  if (v.durationMs > 0 && pos >= v.durationMs * 0.95) return 0;
  return pos;
}

/// Whether a progress bar should be shown (0 < resume < 95 % of duration).
double? progressFraction(Video v) {
  if (v.durationMs <= 0 || v.resumePositionMs <= 0) return null;
  final f = v.resumePositionMs / v.durationMs;
  return f < 0.95 ? f : null;
}

/// True when [positionMs] counts as "finished" (>= 95 %).
bool isFinished(int positionMs, int durationMs) =>
    durationMs > 0 && positionMs >= durationMs * 0.95;

enum VideoSort { newest, oldest, title, recentlyAdded, longest }

extension VideoSortLabel on VideoSort {
  String get label => switch (this) {
        VideoSort.newest => 'Date recorded (newest first)',
        VideoSort.oldest => 'Date recorded (oldest first)',
        VideoSort.title => 'Title A-Z',
        VideoSort.recentlyAdded => 'Recently added',
        VideoSort.longest => 'Longest',
      };
  bool get grouped => this == VideoSort.newest || this == VideoSort.oldest;
}

DateTime effectiveDate(Video v) => v.recordedAt ?? v.fileModifiedAt;

List<Video> filterAndSort(List<Video> all, String query, VideoSort sort) {
  final q = query.trim().toLowerCase();
  final list = q.isEmpty
      ? List<Video>.of(all)
      : all
          .where((v) =>
              v.title.toLowerCase().contains(q) ||
              v.fileName.toLowerCase().contains(q))
          .toList();
  int byDateDesc(Video a, Video b) =>
      effectiveDate(b).compareTo(effectiveDate(a));
  switch (sort) {
    case VideoSort.newest:
      list.sort(byDateDesc);
    case VideoSort.oldest:
      list.sort((a, b) => byDateDesc(b, a));
    case VideoSort.title:
      list.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    case VideoSort.recentlyAdded:
      list.sort((a, b) => b.addedAt.compareTo(a.addedAt));
    case VideoSort.longest:
      list.sort((a, b) => b.durationMs.compareTo(a.durationMs));
  }
  return list;
}

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', 'August',
  'September', 'October', 'November', 'December',
];
const _short = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov',
  'Dec',
];

String monthLabel(DateTime d) => '${_months[d.month - 1]} ${d.year}';
String shortDate(DateTime d) => '${d.day} ${_short[d.month - 1]} ${d.year}';

class MonthGroup {
  MonthGroup(this.label, this.videos);
  final String label;
  final List<Video> videos;
  String get header =>
      '$label · ${videos.length} video${videos.length == 1 ? '' : 's'}';
}

/// Groups an already date-sorted list by calendar month of its effective date.
List<MonthGroup> groupByMonth(List<Video> sorted) {
  final groups = <MonthGroup>[];
  for (final v in sorted) {
    final label = monthLabel(effectiveDate(v).toLocal());
    if (groups.isEmpty || groups.last.label != label) {
      groups.add(MonthGroup(label, []));
    }
    groups.last.videos.add(v);
  }
  return groups;
}

String formatTotalDuration(int ms) {
  final h = ms ~/ 3600000;
  final m = (ms % 3600000) ~/ 60000;
  if (h > 0) return '${h}h ${m}m';
  return '${m}m';
}
