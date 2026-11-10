/// Result of parsing a file name such as "Beach day (Mom, Dad ft. Nani).mp4".
class ParsedName {
  const ParsedName({
    required this.title,
    this.creator,
    this.featured = const [],
  });

  /// Title with the people group removed.
  final String title;
  final String? creator;
  final List<String> featured;

  List<String> get people => [?creator, ...featured];
}

/// Case-insensitive, whitespace-collapsed key used to de-duplicate people.
String personKey(String name) =>
    name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();

String _clean(String s) => s.trim().replaceAll(RegExp(r'\s+'), ' ');

final _group = RegExp(r'\(([^()]*)\)');
final _splitter = RegExp(
  r'\s*(?:,|&|\band\b|\bfeaturing\b|\bfeat\.?(?=\s)|\bft\.?(?=\s))\s*',
  caseSensitive: false,
);
final _ignored = [
  RegExp(r'^\d+$'),
  RegExp(r'^(19|20)\d\d$'),
  RegExp(r'^\d{3,4}p$', caseSensitive: false),
  RegExp(r'^\d+k$', caseSensitive: false),
  RegExp(r'^(copy|final|edit(ed)?|hd|uhd|raw)(\s*\d+)?$', caseSensitive: false),
];

bool _isIgnored(String g) {
  final t = g.trim();
  if (t.isEmpty) return true;
  return _ignored.any((r) => r.hasMatch(t));
}

/// Parses the last meaningful parenthesized group of [baseName] (file name
/// without extension). First person is the creator, the rest are featured.
ParsedName parseName(String baseName) {
  final matches = _group.allMatches(baseName).toList();
  for (var i = matches.length - 1; i >= 0; i--) {
    final m = matches[i];
    final inner = m.group(1)!;
    if (_isIgnored(inner)) continue;
    final seen = <String>{};
    final names = <String>[];
    for (final part in inner.split(_splitter)) {
      final n = _clean(part);
      if (n.isEmpty) continue;
      if (seen.add(personKey(n))) names.add(n);
    }
    if (names.isEmpty) continue;
    final title = _clean(baseName.replaceRange(m.start, m.end, ' '));
    return ParsedName(
      title: title.isEmpty ? _clean(baseName) : title,
      creator: names.first,
      featured: names.skip(1).toList(),
    );
  }
  return ParsedName(title: _clean(baseName));
}

/// Genre = first path segment below [folderPath], or null for files directly
/// in the folder. Handles both / and \ separators.
String? deriveGenre(String filePath, String folderPath) {
  String norm(String p) => p.replaceAll('\\', '/');
  var f = norm(filePath);
  var root = norm(folderPath);
  while (root.endsWith('/') && root.length > 1) {
    root = root.substring(0, root.length - 1);
  }
  if (!f.startsWith('$root/')) return null;
  final rest = f.substring(root.length + 1).split('/');
  if (rest.length < 2) return null;
  final g = _clean(rest.first);
  return g.isEmpty ? null : g;
}
