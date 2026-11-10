import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../widgets/dialogs.dart';

RelativeRect _at(Offset p) => RelativeRect.fromLTRB(p.dx, p.dy, p.dx, p.dy);

void _toast(BuildContext context, String msg) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg)));
}

/// Popup of playlists (most recently updated first) + "New playlist...";
/// appends [videoIds] in the given order.
Future<void> showAddToPlaylistMenu(
    BuildContext context, WidgetRef ref, Offset pos, List<int> videoIds) async {
  if (videoIds.isEmpty) return;
  final lists = ref.read(playlistSummariesProvider);
  final choice = await showMenu<Object>(
    context: context,
    position: _at(pos),
    items: [
      for (final s in lists)
        PopupMenuItem<Object>(
            value: s.playlist.id, child: Text(s.playlist.name)),
      if (lists.isNotEmpty) const PopupMenuDivider(),
      const PopupMenuItem<Object>(
          value: 'new', child: Text('New playlist...')),
    ],
  );
  if (choice == null || !context.mounted) return;
  final db = ref.read(databaseProvider);
  late final int id;
  late final String name;
  if (choice == 'new') {
    final n = await promptName(context,
        title: 'New playlist', action: 'Create');
    if (n == null) return;
    name = n;
    id = await db.createPlaylist(n);
  } else {
    id = choice as int;
    name = lists.firstWhere((s) => s.playlist.id == id).playlist.name;
  }
  await db.addToPlaylist(id, videoIds);
  if (context.mounted) {
    _toast(context, addedMessage(videoIds.length, videoIds.length, name));
  }
}

/// Popup of collections + "New collection..."; skips videos already in it.
Future<void> showAddToCollectionMenu(
    BuildContext context, WidgetRef ref, Offset pos, List<int> videoIds) async {
  if (videoIds.isEmpty) return;
  final lists = ref.read(collectionSummariesProvider);
  final choice = await showMenu<Object>(
    context: context,
    position: _at(pos),
    items: [
      for (final s in lists)
        PopupMenuItem<Object>(
            value: s.collection.id, child: Text(s.collection.name)),
      if (lists.isNotEmpty) const PopupMenuDivider(),
      const PopupMenuItem<Object>(
          value: 'new', child: Text('New collection...')),
    ],
  );
  if (choice == null || !context.mounted) return;
  final db = ref.read(databaseProvider);
  late final int id;
  late final String name;
  if (choice == 'new') {
    final n = await promptName(context,
        title: 'New collection', action: 'Create');
    if (n == null) return;
    id = await db.createCollection(n);
    // createCollection returns the existing row on a case-insensitive match.
    name = ref
            .read(collectionSummariesProvider)
            .where((s) => s.collection.id == id)
            .map((s) => s.collection.name)
            .firstOrNull ??
        n;
  } else {
    id = choice as int;
    name = lists.firstWhere((s) => s.collection.id == id).collection.name;
  }
  final added = await db.addToCollection(id, videoIds);
  if (context.mounted) {
    _toast(context, addedMessage(added, videoIds.length, name));
  }
}

/// Screen position just under a button, for anchoring a popup to it.
Offset anchorBelow(BuildContext context) {
  final box = context.findRenderObject() as RenderBox;
  return box.localToGlobal(Offset(0, box.size.height));
}
