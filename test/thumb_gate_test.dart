import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/library/thumb_gate.dart';

void main() {
  const delay = Duration(milliseconds: 60);
  const pastDelay = Duration(milliseconds: 150);

  test('starts allowed', () async {
    final g = ThumbGate(resumeDelay: delay);
    expect(g.allowed, isTrue);
    await g.whenAllowed();
  });

  test('playing blocks immediately', () {
    final g = ThumbGate(resumeDelay: delay)..setPlaying(true);
    expect(g.allowed, isFalse);
    expect(g.playing, isTrue);
  });

  test('resumes only after the delay once playback stops', () async {
    final g = ThumbGate(resumeDelay: delay)..setPlaying(true);
    var released = false;
    final f = g.whenAllowed().then((_) => released = true);
    g.setPlaying(false);
    expect(g.allowed, isFalse);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(released, isFalse);
    await f;
    expect(g.allowed, isTrue);
  });

  test('playing again during the delay cancels the resume', () async {
    final g = ThumbGate(resumeDelay: delay)..setPlaying(true);
    g.setPlaying(false);
    await Future<void>.delayed(const Duration(milliseconds: 20));
    g.setPlaying(true);
    await Future<void>.delayed(pastDelay);
    expect(g.allowed, isFalse);
    g.setPlaying(false);
    await Future<void>.delayed(pastDelay);
    expect(g.allowed, isTrue);
  });

  test('close releases waiters and stays open', () async {
    final g = ThumbGate(resumeDelay: delay)..setPlaying(true);
    final f = g.whenAllowed();
    g.close();
    await f;
    g.setPlaying(true);
    expect(g.allowed, isTrue);
    await g.whenAllowed();
  });
}
