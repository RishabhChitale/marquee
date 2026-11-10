import 'package:flutter_test/flutter_test.dart';
import 'package:marquee/core/player/play_queue.dart';

void main() {
  test('empty queue has no current/next/previous', () {
    final q = PlayQueue();
    expect(q.current, isNull);
    expect(q.next(), isNull);
    expect(q.previous(), isNull);
  });

  test('next and previous walk the queue and stop at the ends', () {
    final q = PlayQueue()..setItems(['a', 'b', 'c']);
    expect(q.current, 'a');
    expect(q.previous(), isNull);
    expect(q.next(), 'b');
    expect(q.next(), 'c');
    expect(q.next(), isNull);
    expect(q.current, 'c');
    expect(q.previous(), 'b');
    expect(q.hasPrevious, isTrue);
    expect(q.hasNext, isTrue);
  });

  test('select appends unknown paths and reuses known ones', () {
    final q = PlayQueue()..setItems(['a', 'b']);
    q.select('b');
    expect(q.index, 1);
    q.select('z');
    expect(q.items, ['a', 'b', 'z']);
    expect(q.current, 'z');
  });
}
