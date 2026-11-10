import 'dart:convert';
import 'dart:io';

/// Where a downloaded video came from (read-only, from local metadata).
class VideoSource {
  const VideoSource(this.url, this.domain);
  final String url;
  final String domain;
}

const _cdnHosts = [
  'googlevideo.com',
  'cdninstagram.com',
  'fbcdn.net',
  'twimg.com',
  'akamaized.net',
];

bool domainIsCdn(String host) => _isCdn(host);

bool _isCdn(String host) =>
    _cdnHosts.any((c) => host == c || host.endsWith('.$c'));

String? domainOf(String url) {
  final u = Uri.tryParse(url.trim());
  if (u == null || !(u.scheme == 'http' || u.scheme == 'https')) return null;
  var h = u.host.toLowerCase();
  if (h.isEmpty) return null;
  if (h.startsWith('www.')) h = h.substring(4);
  return h;
}

final _urlRe = RegExp(r'''https?://[^\s"'<>\)\]]+''', caseSensitive: false);

/// Picks the best source from candidate URLs: the first non-CDN http(s) URL,
/// else the first valid one.
VideoSource? pickSource(Iterable<String> candidates) {
  VideoSource? fallback;
  for (final c in candidates) {
    final d = domainOf(c);
    if (d == null) continue;
    final s = VideoSource(c.trim(), d);
    if (!_isCdn(d)) return s;
    fallback ??= s;
  }
  return fallback;
}

/// Extracts URLs from container tag values (purl, comment, ...).
List<String> urlsFromText(Iterable<String?> values) => [
  for (final v in values)
    if (v != null) ...[for (final m in _urlRe.allMatches(v)) m.group(0)!],
];

/// Parses the JSON plutil prints for kMDItemWhereFroms (an array of strings).
List<String> parseWhereFromsJson(String json) {
  try {
    final d = jsonDecode(json);
    if (d is List) {
      return [
        for (final e in d)
          if (e is String) e,
      ];
    }
  } catch (_) {}
  return const [];
}

/// Parses Windows Zone.Identifier text: ReferrerUrl first, then HostUrl.
List<String> parseZoneIdentifier(String text) {
  String? referrer, host;
  for (final line in const LineSplitter().convert(text)) {
    final i = line.indexOf('=');
    if (i < 0) continue;
    final k = line.substring(0, i).trim().toLowerCase();
    final v = line.substring(i + 1).trim();
    if (k == 'referrerurl') referrer = v;
    if (k == 'hosturl') host = v;
  }
  return [?referrer, ?host];
}

/// Reads the browser-download attribute from the file's own OS metadata.
/// Read-only; never modifies the file; no network.
Future<List<String>> readDownloadOrigin(String path) async {
  try {
    if (Platform.isMacOS) {
      final x = await Process.run('/usr/bin/xattr', [
        '-px',
        'com.apple.metadata:kMDItemWhereFroms',
        path,
      ]);
      if (x.exitCode != 0) return const [];
      final hex = (x.stdout as String).replaceAll(RegExp(r'\s'), '');
      if (hex.isEmpty || hex.length.isOdd) return const [];
      final bytes = <int>[
        for (var i = 0; i < hex.length; i += 2)
          int.parse(hex.substring(i, i + 2), radix: 16),
      ];
      final p = await Process.start('/usr/bin/plutil', [
        '-convert',
        'json',
        '-o',
        '-',
        '-',
      ]);
      p.stdin.add(bytes);
      await p.stdin.close();
      final out = await utf8.decodeStream(p.stdout);
      await p.stderr.drain<void>();
      if (await p.exitCode != 0) return const [];
      return parseWhereFromsJson(out);
    }
    if (Platform.isWindows) {
      final f = File('$path:Zone.Identifier');
      return parseZoneIdentifier(await f.readAsString());
    }
  } catch (_) {}
  return const [];
}
