// Spike: proves the libmpv bundled with media_kit has the `pcm` audio output
// (ao=pcm), which Milestone 5 uses to cut audio clips without ffmpeg.
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:media_kit/media_kit.dart';

Uint8List _toneWav(int seconds) {
  const rate = 16000;
  final n = rate * seconds;
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
  b.setUint32(24, rate, Endian.little);
  b.setUint32(28, rate * 2, Endian.little);
  b.setUint16(32, 2, Endian.little);
  b.setUint16(34, 16, Endian.little);
  s(36, 'data');
  b.setUint32(40, n * 2, Endian.little);
  for (var i = 0; i < n; i++) {
    b.setInt16(
      44 + i * 2,
      (8000 * math.sin(2 * math.pi * 440 * i / rate)).round(),
      Endian.little,
    );
  }
  return b.buffer.asUint8List();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  testWidgets('libmpv has ao=pcm and dumps a WAV', (tester) async {
    final dir = await Directory.systemTemp.createTemp('marquee_pcm');
    final src = File('${dir.path}/tone.wav')..writeAsBytesSync(_toneWav(5));
    final out = File('${dir.path}/clip.wav');

    final player = Player();
    final native = player.platform as NativePlayer;
    await native.setProperty('vid', 'no');
    await native.setProperty('sid', 'no');
    await native.setProperty('ao', 'pcm');
    await native.setProperty('ao-pcm-file', out.path);
    await native.setProperty('ao-pcm-waveheader', 'yes');
    await native.setProperty('untimed', 'yes');
    await native.setProperty('start', '1');
    await native.setProperty('length', '2');
    await native.setProperty('audio-channels', 'mono');
    await native.setProperty('audio-samplerate', '16000');

    final done = Completer<void>();
    final sub = player.stream.completed.listen((c) {
      if (c && !done.isCompleted) done.complete();
    });
    await player.open(Media(src.path));
    await done.future.timeout(const Duration(seconds: 20));
    await sub.cancel();
    final ao = await native.getProperty('current-ao');
    await player.dispose();

    final bytes = out.readAsBytesSync();
    // ignore: avoid_print
    print('AO_PCM_PROOF current-ao=$ao wav_bytes=${bytes.length} '
        'header=${String.fromCharCodes(bytes.sublist(0, 4))}'
        '/${String.fromCharCodes(bytes.sublist(8, 12))}');
    expect(ao, 'pcm');
    expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
    // 2 s of 16 kHz mono s16 = 64000 bytes of audio (+ header).
    expect(bytes.length, greaterThan(50000));
    await dir.delete(recursive: true);
  });
}
