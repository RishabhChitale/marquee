import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/player/time_format.dart';

void main() {
  test('formats seconds', () {
    expect(formatSeconds(0), '0:00');
    expect(formatSeconds(65), '1:05');
    expect(formatSeconds(3725), '1:02:05');
  });

  test('formats Duration and clamps negatives', () {
    expect(formatTime(const Duration(minutes: 10, seconds: 9)), '10:09');
    expect(formatTime(const Duration(seconds: -5)), '0:00');
  });
}
