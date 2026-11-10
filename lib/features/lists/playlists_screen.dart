import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_logic.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/video_thumb.dart';

class PlaylistsScreen extends ConsumerWidget {
  const PlaylistsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptName(context,
        title: 'New playlist', action: 'Create');
    if (name == null) return;
    final id = await ref.read(databaseProvider).createPlaylist(name);
    if (context.mounted) context.go('/playlists/$id');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset pos,
      PlaylistSummary s) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: const [
        PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
    if (choice == null || !context.mounted) return;
    final db = ref.read(databaseProvider);
    if (choice == 'rename') {
      final n = await promptName(context,
          title: 'Rename playlist', initial: s.playlist.name);
      if (n != null) await db.renamePlaylist(s.playlist.id, n);
    } else {
      final ok = await confirmDialog(context,
          title: 'Delete playlist?',
          message:
              'Delete "${s.playlist.name}"? Only the playlist is deleted; '
              'your videos stay in the library.',
          action: 'Delete');
      if (ok) await db.deletePlaylist(s.playlist.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final lists = ref.watch(playlistSummariesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(children: [
            Text('Playlists',
                style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New playlist'),
            ),
          ]),
        ),
        Expanded(
          child: lists.isEmpty
              ? const Center(child: Text('No playlists yet.'))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: lists.length,
                  itemBuilder: (_, i) {
                    final s = lists[i];
                    return GestureDetector(
                      onSecondaryTapUp: (d) =>
                          _menu(context, ref, d.globalPosition, s),
                      child: ListTile(
                        leading: SizedBox(
                          width: 96,
                          height: 54,
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: VideoThumb(s.first)),
                        ),
                        title: Text(s.playlist.name),
                        subtitle: Text(
                            '${videoCountLabel(s.count)}'
                            '${s.totalMs > 0 ? ' · ${formatTotalDuration(s.totalMs)}' : ''}'),
                        onTap: () => context.go('/playlists/${s.playlist.id}'),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
