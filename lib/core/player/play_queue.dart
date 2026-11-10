/// Pure-Dart play queue: an ordered list of paths with a current index.
class PlayQueue {
  PlayQueue([List<String> items = const []]) : _items = List.of(items);

  final List<String> _items;
  int _index = -1;

  List<String> get items => List.unmodifiable(_items);
  int get index => _index;
  String? get current =>
      _index >= 0 && _index < _items.length ? _items[_index] : null;
  bool get hasNext => _index + 1 < _items.length;
  bool get hasPrevious => _index > 0;

  /// Appends [path] and returns its index.
  int add(String path) {
    _items.add(path);
    return _items.length - 1;
  }

  /// Replaces the queue with [paths] and selects [start].
  void setItems(List<String> paths, {int start = 0}) {
    _items
      ..clear()
      ..addAll(paths);
    _index = paths.isEmpty ? -1 : start.clamp(0, paths.length - 1);
  }

  /// Makes [path] current, appending it if absent. Returns it.
  String select(String path) {
    var i = _items.indexOf(path);
    if (i < 0) i = add(path);
    _index = i;
    return path;
  }

  /// Advances and returns the new current path, or null at the end.
  String? next() {
    if (!hasNext) return null;
    _index++;
    return _items[_index];
  }

  /// Steps back and returns the new current path, or null at the start.
  String? previous() {
    if (!hasPrevious) return null;
    _index--;
    return _items[_index];
  }
}
