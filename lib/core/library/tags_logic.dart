import '../db/database.dart';

class PersonRef {
  const PersonRef(this.name, this.key, this.isCreator);
  final String name;
  final String key;
  final bool isCreator;
}

typedef PeopleByVideo = Map<int, List<PersonRef>>;

/// Builds videoId -> people (creator first) from the two DB tables.
PeopleByVideo buildPeopleIndex(
  List<PeopleData> people,
  List<VideoPeopleData> links,
) {
  final byId = {for (final p in people) p.id: p};
  final out = <int, List<PersonRef>>{};
  for (final l in links) {
    final p = byId[l.personId];
    if (p == null) continue;
    (out[l.videoId] ??= []).add(
      PersonRef(p.name, p.nameKey, l.role == 'creator'),
    );
  }
  for (final l in out.values) {
    l.sort((a, b) => a.isCreator == b.isCreator ? 0 : (a.isCreator ? -1 : 1));
  }
  return out;
}

class TagFilter {
  const TagFilter({this.genre, this.personKey});
  final String? genre;
  final String? personKey;
  bool get active => genre != null || personKey != null;
}

bool _genreOk(Video v, String? genre) => genre == null || v.genre == genre;
bool _personOk(int id, PeopleByVideo idx, String? key) =>
    key == null || (idx[id]?.any((p) => p.key == key) ?? false);

/// Genre AND person (either role).
List<Video> applyTagFilter(List<Video> all, PeopleByVideo idx, TagFilter f) => [
  for (final v in all)
    if (_genreOk(v, f.genre) && _personOk(v.id, idx, f.personKey)) v,
];

class TagCount {
  const TagCount(this.label, this.key, this.count);
  final String label;
  final String key;
  final int count;
}

int _byCountThenName(TagCount a, TagCount b) {
  final c = b.count.compareTo(a.count);
  return c != 0 ? c : a.label.toLowerCase().compareTo(b.label.toLowerCase());
}

/// Genre chips; counts respect the selected person only.
List<TagCount> genreCounts(
  List<Video> all,
  PeopleByVideo idx,
  String? personKey,
) {
  final m = <String, int>{};
  for (final v in all) {
    if (v.genre == null || !_personOk(v.id, idx, personKey)) continue;
    m[v.genre!] = (m[v.genre!] ?? 0) + 1;
  }
  return [for (final e in m.entries) TagCount(e.key, e.key, e.value)]
    ..sort(_byCountThenName);
}

/// People chips; counts respect the selected genre only.
List<TagCount> personCounts(List<Video> all, PeopleByVideo idx, String? genre) {
  final m = <String, int>{};
  final names = <String, String>{};
  for (final v in all) {
    if (!_genreOk(v, genre)) continue;
    for (final p in idx[v.id] ?? const <PersonRef>[]) {
      m[p.key] = (m[p.key] ?? 0) + 1;
      names.putIfAbsent(p.key, () => p.name);
    }
  }
  return [for (final e in m.entries) TagCount(names[e.key]!, e.key, e.value)]
    ..sort(_byCountThenName);
}

/// "by Riya · ft. Dad, Nani" (null when no people).
String? peopleLine(List<PersonRef>? people) {
  if (people == null || people.isEmpty) return null;
  final c = people.where((p) => p.isCreator).toList();
  final f = people.where((p) => !p.isCreator).map((p) => p.name).toList();
  final parts = <String>[
    if (c.isNotEmpty) 'by ${c.first.name}',
    if (f.isNotEmpty) 'ft. ${f.join(', ')}',
  ];
  return parts.join(' · ');
}
