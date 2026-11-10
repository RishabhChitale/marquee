import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_logic.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/time_format.dart';
import '../../widgets/video_thumb.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  const PlaylistDetailScreen({super.key, required this.playlistId});
  final int playlistId;

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _State();
}

class _State extends ConsumerState<PlaylistDetailScreen> {
  /// Optimistic order while a drag is being persisted.
  List<int>? _order;

  Future<void> _play(List<PlaylistEntry> entries,
      {int startAt = 0, bool shuffle = false}) async {
    final playable = entries.where((e) => !e.video.missing).toList();
    if (playable.isEmpty) return;
    List<PlaylistEntry> queue = playable;
    var index = 0;
    if (shuffle) {
      queue = shuffledCopy(playable);
    } else {
      final start = entries[startAt];
      index = playable.indexWhere((e) => e.item.id == start.item.id);
      if (index < 0) index = 0;
    }
    final paths = [for (final e in queue) e.video.path];
    await ref
        .read(playerControllerProvider)
        .playList(paths, paths[index], startIndex: index);
    if (mounted) context.go('/player');
  }

  @override
  Widget build(BuildContext context) {
    final s = ref
        .watch(playlistSummariesProvider)
        .where((p) => p.playlist.id == widget.playlistId)
        .firstOrNull;
    if (s == null) {
      return const Center(child: Text('Playlist not found.'));
    }
    var entries = s.entries;
    if (_order != null && _order!.length == entries.length) {
      final byId = {for (final e in entries) e.item.id: e};
      if (_order!.every(byId.containsKey)) {
        entries = [for (final id in _order!) byId[id]!];
      }
    }
    final db = ref.read(databaseProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
          child: Row(children: [
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back),
              onPressed: () => context.go('/playlists'),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(s.playlist.name,
                    style: Theme.of(context).textTheme.headlineSmall),
                Text(
                    '${videoCountLabel(s.count)}'
                    '${s.totalMs > 0 ? ' · ${formatTotalDuration(s.totalMs)}' : ''}',
                    style: Theme.of(context).textTheme.bodySmall),
              ],
            ),
            const Spacer(),
            OutlinedButton.icon(
              onPressed: entries.isEmpty
                  ? null
                  : () => _play(entries, shuffle: true),
              icon: const Icon(Icons.shuffle),
              label: const Text('Shuffle'),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              onPressed: entries.isEmpty ? null : () => _play(entries),
              icon: const Icon(Icons.play_arrow),
              label: const Text('Play all'),
            ),
          ]),
        ),
        Expanded(
          child: entries.isEmpty
              ? const Center(
                  child: Text('Empty. Add videos from the Library.'))
              : ReorderableListView.builder(
                  buildDefaultDragHandles: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: entries.length,
                  onReorderItem: (from, to) async {
                    final ids = [for (final e in entries) e.item.id];
                    ids.insert(to, ids.removeAt(from));
                    setState(() => _order = ids);
                    await db.reorderPlaylist(s.playlist.id, ids);
                    if (mounted) setState(() => _order = null);
                  },
                  itemBuilder: (_, i) {
                    final e = entries[i];
                    final v = e.video;
                    return Opacity(
                      key: ValueKey(e.item.id),
                      opacity: v.missing ? 0.4 : 1,
                      child: ListTile(
                        leading: SizedBox(
                          width: 96,
                          height: 54,
                          child: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: VideoThumb(v)),
                        ),
                        title: Text(v.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if (v.durationMs > 0)
                            formatSeconds(v.durationMs ~/ 1000),
                          shortDate(effectiveDate(v).toLocal()),
                          if (v.missing) 'Drive not connected',
                        ].join(' · ')),
                        trailing: Padding(
                          padding: const EdgeInsets.only(right: 32),
                          child: IconButton(
                            tooltip: 'Remove from playlist',
                            icon: const Icon(Icons.close),
                            onPressed: () => db.removePlaylistItem(e.item.id),
                          ),
                        ),
                        onTap: v.missing ? null : () => _play(entries, startAt: i),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
