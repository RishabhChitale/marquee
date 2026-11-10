import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:marquee/core/library/thumb_gate.dart';
import 'package:marquee/core/music/audd_client.dart';
import 'package:marquee/core/music/clip_extractor.dart';
import 'package:marquee/core/music/dedupe.dart';
import 'package:marquee/core/music/sampling.dart';
import 'package:marquee/core/music/scan_engine.dart';
import 'package:marquee/core/music/token_store.dart';

const _match = '{"status":"success","result":{"artist":"Daft Punk",'
    '"title":"Get Lucky","album":"RAM","release_date":"2013-04-19",'
    '"label":"Columbia","song_link":"https://lis.tn/x",'
    '"spotify":{"external_urls":{"spotify":"https://open.spotify.com/t"}},'
    '"apple_music":{"url":"https://music.apple.com/t"}}}';

class _FakeSource implements ClipSource {
  final calls = <int>[];
  @override
  Future<Uint8List?> extract(String path, int o, int l) async {
    calls.add(o);
    return Uint8List.fromList([1, 2, 3]);
  }

  @override
  Future<void> dispose() async {}
}

class _Sink implements ScanSink {
  final saved = <int, List<FoundSong>>{};
  final failed = <int, bool>{};
  @override
  Future<void> save(int id, List<FoundSong> s, {required bool failed}) async {
    saved[id] = s;
    this.failed[id] = failed;
  }
}

AuddMatch _m(String a, String t) => AuddMatch(artist: a, title: t);

void main() {
  group('parse', () {
    test('match', () {
      final m = parseAuddResponse(_match)!;
      expect(m.artist, 'Daft Punk');
      expect(m.title, 'Get Lucky');
      expect(m.album, 'RAM');
      expect(m.spotifyUrl, 'https://open.spotify.com/t');
      expect(m.appleMusicUrl, 'https://music.apple.com/t');
      expect(m.songLink, 'https://lis.tn/x');
    });
    test('no match', () {
      expect(parseAuddResponse('{"status":"success","result":null}'), isNull);
    });
    test('error', () {
      expect(
        () => parseAuddResponse('{"status":"error","error":'
            '{"error_code":901,"error_message":"No requests left"}}'),
        throwsA(isA<AuddApiError>()
            .having((e) => e.code, 'code', 901)
            .having((e) => e.fatal, 'fatal', true)
            .having((e) => e.message, 'msg', 'No requests left')),
      );
    });
    test('garbage is a network error', () {
      expect(() => parseAuddResponse('<html>'),
          throwsA(isA<AuddNetworkError>()));
    });
  });

  test('request carries only api_token, file, return', () async {
    late http.BaseRequest seen;
    late String body;
    final client = MockClient.streaming((req, stream) async {
      seen = req;
      body = latin1.decode(await stream.expand((c) => c).toList());
      return http.StreamedResponse(Stream.value(utf8.encode(_match)), 200);
    });
    final m = await AuddClient(client: client)
        .recognize(Uint8List.fromList([9, 9, 9]), 'tok123');
    expect(m!.title, 'Get Lucky');
    expect(seen.url.toString(), 'https://api.audd.io/');
    expect(seen.method, 'POST');
    final names = RegExp(r'form-data; name="([^"]+)"')
        .allMatches(body)
        .map((x) => x.group(1))
        .toSet();
    expect(names, {'api_token', 'return', 'file'});
    expect(body, contains('apple_music,spotify'));
    expect(body, contains('tok123'));
  });

  group('sampling', () {
    test('N=1', () {
      expect(planClips(100000, 1).map((c) => c.offsetMs), [50000]);
    });
    test('N=2', () {
      expect(planClips(100000, 2).map((c) => c.offsetMs), [30000, 70000]);
    });
    test('N=3', () {
      expect(
          planClips(100000, 3).map((c) => c.offsetMs), [15000, 50000, 85000]);
    });
    test('clamped to the end', () {
      final c = planClips(60000, 3).last; // 85% = 51000, +12000 > 60000
      expect(c.offsetMs + c.lengthMs, 60000);
      expect(c.lengthMs, 12000);
    });
    test('short videos', () {
      expect(planClips(7999, 3), isEmpty);
      expect(planClips(0, 3), isEmpty);
      final c = planClips(10000, 1).single; // shorter than a clip
      expect(c.offsetMs, 0);
      expect(c.lengthMs, 10000);
    });
  });

  test('dedupe keeps earliest offset, case-insensitive', () {
    final out = dedupeHits(const [
      SongHit(50000, 'Daft Punk', 'Get Lucky', null),
      SongHit(15000, 'daft punk', 'GET LUCKY', null),
      SongHit(85000, 'Other', 'Song', null),
    ]);
    expect(out.map((h) => h.offsetMs), [15000, 85000]);
  });

  group('token store', () {
    late Directory app, home;
    setUp(() {
      app = Directory.systemTemp.createTempSync('app');
      home = Directory.systemTemp.createTempSync('home');
    });
    tearDown(() {
      app.deleteSync(recursive: true);
      home.deleteSync(recursive: true);
    });
    test('fallback order and save/remove', () async {
      final s = TokenStore(appSupportDir: app.path, homeDir: home.path);
      expect(await s.read(), isNull);
      File('${home.path}/.config/marquee/audd_token')
        ..createSync(recursive: true)
        ..writeAsStringSync('fallback\n');
      expect(await s.read(), 'fallback');
      await s.save(' apptoken ');
      expect(await s.read(), 'apptoken');
      if (Platform.isMacOS || Platform.isLinux) {
        expect(s.appFile.statSync().mode & 0x1ff, 0x180); // 600
      }
      await s.remove();
      expect(await s.read(), 'fallback');
    });
  });

  group('scan engine', () {
    ScanEngine make(Recognizer r, _Sink sink, _FakeSource src,
            {ThumbGate? gate, int clips = 1}) =>
        ScanEngine(
          source: src,
          recognize: r,
          sink: sink,
          token: 't',
          clipCount: clips,
          gate: gate,
          gap: Duration.zero,
        );
    const v1 = ScanVideo(1, '/a', 100000);
    const v2 = ScanVideo(2, '/b', 100000);

    test('saves matches, skips short videos', () async {
      final sink = _Sink();
      final e = make((w, t) async => _m('A', 'B'), sink, _FakeSource());
      final p = await e.run(const [v1, ScanVideo(3, '/c', 1000)]);
      expect(p.phase, ScanPhase.done);
      expect(p.total, 1);
      expect(sink.saved.keys, [1]);
      expect(sink.saved[1]!.single.match.title, 'B');
    });

    test('fatal error stops the scan', () async {
      final sink = _Sink();
      final e = make(
          (w, t) async => throw const AuddApiError(901, 'No requests left'),
          sink,
          _FakeSource());
      final p = await e.run(const [v1, v2]);
      expect(p.phase, ScanPhase.stopped);
      expect(p.error, 'No requests left');
      expect(sink.saved, isEmpty);
    });

    test('network error retries once then continues', () async {
      final sink = _Sink();
      var n = 0;
      final e = make((w, t) async {
        n++;
        if (n == 1) throw const AuddNetworkError('x');
        return _m('A', 'B');
      }, sink, _FakeSource());
      await e.run(const [v1]);
      expect(n, 2);
      expect(sink.failed[1], false);
      expect(sink.saved[1], hasLength(1));
    });

    test('two network errors mark the video failed and move on', () async {
      final sink = _Sink();
      final e = make((w, t) async {
        if (t == 't' && sink.saved.isEmpty) throw const AuddNetworkError('x');
        return _m('A', 'B');
      }, sink, _FakeSource());
      await e.run(const [v1, v2]);
      expect(sink.failed[1], true);
      expect(sink.failed[2], false);
    });

    test('cancel stops before the next clip', () async {
      final sink = _Sink();
      late ScanEngine e;
      e = make((w, t) async {
        e.cancel();
        return null;
      }, sink, _FakeSource());
      final p = await e.run(const [v1, v2]);
      expect(p.phase, ScanPhase.cancelled);
      expect(sink.saved, isEmpty);
    });

    test('pause holds the scan until resume', () async {
      final sink = _Sink();
      final src = _FakeSource();
      final e = make((w, t) async => null, sink, src);
      e.pause(); // ignored: not running yet
      final fut = e.run(const [v1, v2]);
      await Future<void>.delayed(Duration.zero);
      e.pause();
      final before = src.calls.length;
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(src.calls.length, before);
      expect(e.phase, ScanPhase.paused);
      e.resume();
      final p = await fut;
      expect(p.phase, ScanPhase.done);
      expect(src.calls.length, 2);
    });

    test('waits while the visible player plays', () async {
      final gate = ThumbGate(resumeDelay: const Duration(milliseconds: 30))
        ..setPlaying(true);
      final src = _FakeSource();
      final e = make((w, t) async => null, _Sink(), src, gate: gate);
      final fut = e.run(const [v1]);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      expect(src.calls, isEmpty);
      gate.setPlaying(false);
      await fut;
      expect(src.calls, hasLength(1));
    });
  });
}
