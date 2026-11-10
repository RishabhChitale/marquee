import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// The ONLY file in lib/ that talks to the network.
///
/// It sends a short WAV clip, the API token and the `return` field to
/// https://api.audd.io/ and nothing else: never file names, paths, video,
/// thumbnails or other metadata.
const auddEndpoint = 'https://api.audd.io/';
const auddReturn = 'apple_music,spotify';

class AuddMatch {
  const AuddMatch({
    required this.artist,
    required this.title,
    this.album,
    this.releaseDate,
    this.label,
    this.songLink,
    this.spotifyUrl,
    this.appleMusicUrl,
  });
  final String artist;
  final String title;
  final String? album;
  final String? releaseDate;
  final String? label;
  final String? songLink;
  final String? spotifyUrl;
  final String? appleMusicUrl;
}

/// An error reported by AudD itself (status 'error').
class AuddApiError implements Exception {
  const AuddApiError(this.code, this.message);
  final int code;
  final String message;

  /// Bad token, missing token, or quota/limit problems: retrying every other
  /// clip would fail the same way, so the whole scan stops.
  bool get fatal => code >= 900 && code < 1000;

  @override
  String toString() => 'AudD error $code: $message';
}

/// Connection problem, timeout or an unreadable reply.
class AuddNetworkError implements Exception {
  const AuddNetworkError(this.message);
  final String message;
  @override
  String toString() => message;
}

String? _str(Object? v) {
  if (v is! String) return null;
  final t = v.trim();
  return t.isEmpty ? null : t;
}

/// Parses AudD's JSON. Returns null for "no match"; throws [AuddApiError] for
/// status 'error'.
AuddMatch? parseAuddResponse(String body) {
  final Object? json;
  try {
    json = jsonDecode(body);
  } on FormatException {
    throw const AuddNetworkError('Unreadable reply from AudD');
  }
  if (json is! Map) throw const AuddNetworkError('Unreadable reply from AudD');
  final status = json['status'];
  if (status == 'error') {
    final e = json['error'];
    final code = e is Map && e['error_code'] is num
        ? (e['error_code'] as num).toInt()
        : 0;
    final msg = e is Map ? (_str(e['error_message']) ?? 'Unknown error') : 'Unknown error';
    throw AuddApiError(code, msg);
  }
  if (status != 'success') {
    throw const AuddNetworkError('Unexpected reply from AudD');
  }
  final r = json['result'];
  if (r is! Map) return null;
  final artist = _str(r['artist']);
  final title = _str(r['title']);
  if (artist == null || title == null) return null;
  String? spotify;
  final sp = r['spotify'];
  if (sp is Map) {
    final ext = sp['external_urls'];
    if (ext is Map) spotify = _str(ext['spotify']);
  }
  String? apple;
  final am = r['apple_music'];
  if (am is Map) apple = _str(am['url']);
  return AuddMatch(
    artist: artist,
    title: title,
    album: _str(r['album']),
    releaseDate: _str(r['release_date']),
    label: _str(r['label']),
    songLink: _str(r['song_link']),
    spotifyUrl: spotify,
    appleMusicUrl: apple,
  );
}

class AuddClient {
  AuddClient({http.Client? client}) : _client = client ?? http.Client();
  final http.Client _client;

  /// One recognition request. Throws [AuddApiError] / [AuddNetworkError].
  Future<AuddMatch?> recognize(Uint8List wav, String token) async {
    final req = http.MultipartRequest('POST', Uri.parse(auddEndpoint))
      ..fields['api_token'] = token
      ..fields['return'] = auddReturn
      ..files.add(
        http.MultipartFile.fromBytes('file', wav, filename: 'clip.wav'),
      );
    final http.Response res;
    try {
      res = await http.Response.fromStream(
        await _client.send(req).timeout(const Duration(seconds: 60)),
      );
    } on TimeoutException {
      throw const AuddNetworkError('Request to AudD timed out');
    } catch (e) {
      if (e is AuddNetworkError || e is AuddApiError) rethrow;
      throw const AuddNetworkError('Could not reach AudD');
    }
    if (res.statusCode >= 500) {
      throw AuddNetworkError('AudD server error (${res.statusCode})');
    }
    return parseAuddResponse(res.body);
  }

  /// Cheapest possible check: 0.2 s of silence. OK means the token is valid.
  Future<void> testToken(String token) async {
    await recognize(silentWav(), token);
  }

  void close() => _client.close();
}

/// 0.2 s of 16 kHz mono silence as a WAV.
Uint8List silentWav() {
  const n = 3200;
  final b = ByteData(44 + n * 2);
  void s(int o, String t) {
    for (var i = 0; i < 4; i++) {
      b.setUint8(o + i, t.codeUnitAt(i));
    }
  }

  s(0, 'RIFF');
  b.setUint32(4, 36 + n * 2, Endian.little);
  s(8, 'WAVE');
  s(12, 'fmt ');
  b.setUint32(16, 16, Endian.little);
  b.setUint16(20, 1, Endian.little);
  b.setUint16(22, 1, Endian.little);
  b.setUint32(24, 16000, Endian.little);
  b.setUint32(28, 32000, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  return b.buffer.asUint8List();
}
