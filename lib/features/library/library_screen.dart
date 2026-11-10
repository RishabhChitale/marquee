import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/library/library_logic.dart';
import '../../core/library/library_providers.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/time_format.dart';

class LibraryScreen extends ConsumerWidget {
  const LibraryScreen({super.key});

  Future<void> _addFolder(WidgetRef ref) async {
    final dir = await FilePicker.platform.getDirectoryPath();
    if (dir != null) {
      await ref.read(libraryServiceProvider.notifier).addFolder(dir);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final all = ref.watch(videosProvider).value ?? const <Video>[];
    final folders = ref.watch(foldersProvider).value ?? const <LibraryFolder>[];
    final visible = ref.watch(visibleVideosProvider);
    final sort = ref.watch(sortProvider);
    final scan = ref.watch(libraryServiceProvider);
    final totalMs = visible.fold<int>(0, (a, v) => a + v.durationMs);

    final subtitle = scan.scanning
        ? 'Scanning... ${scan.found} videos found'
        : '${visible.length} video${visible.length == 1 ? '' : 's'}'
            '${totalMs > 0 ? ' · ${formatTotalDuration(totalMs)}' : ''}';

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Library',
                      style: Theme.of(context).textTheme.headlineSmall),
                  Text(subtitle,
                      style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(width: 24),
              Expanded(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 360),
                  child: TextField(
                    decoration: const InputDecoration(
                      isDense: true,
                      prefixIcon: Icon(Icons.search),
                      hintText: 'Search title or file name',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (v) =>
                        ref.read(searchProvider.notifier).set(v),
                  ),
                ),
              ),
              const Spacer(),
              PopupMenuButton<VideoSort>(
                tooltip: 'Sort',
                initialValue: sort,
                icon: const Icon(Icons.sort),
                onSelected: ref.read(sortProvider.notifier).set,
                itemBuilder: (_) => [
                  for (final s in VideoSort.values)
                    CheckedPopupMenuItem(
                        value: s, checked: s == sort, child: Text(s.label)),
                ],
              ),
              IconButton(
                tooltip: 'Folders',
                icon: const Icon(Icons.folder_copy_outlined),
                onPressed: () => showDialog<void>(
                    context: context,
                    builder: (_) => const _FoldersDialog()),
              ),
              IconButton(
                tooltip: 'Rescan',
                icon: const Icon(Icons.refresh),
                onPressed: scan.scanning
                    ? null
                    : () => ref.read(libraryServiceProvider.notifier).rescan(),
              ),
              const SizedBox(width: 8),
              FilledButton.icon(
                onPressed: () => _addFolder(ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add folder'),
              ),
            ],
          ),
        ),
        Expanded(
          child: folders.isEmpty && all.isEmpty
              ? Center(
                  child: FilledButton.icon(
                    onPressed: () => _addFolder(ref),
                    icon: const Icon(Icons.create_new_folder_outlined),
                    label: const Text('Add a folder of home videos'),
                  ),
                )
              : visible.isEmpty
                  ? Center(
                      child: Text(scan.scanning
                          ? 'Scanning...'
                          : 'No videos match.'))
                  : _Timeline(videos: visible, grouped: sort.grouped),
        ),
      ],
    );
  }
}

class _Timeline extends StatelessWidget {
  const _Timeline({required this.videos, required this.grouped});
  final List<Video> videos;
  final bool grouped;

  static const _delegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 280,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: 1.45,
  );

  SliverGrid _grid(List<Video> vs) => SliverGrid(
        gridDelegate: _delegate,
        delegate: SliverChildBuilderDelegate(
          (_, i) => _VideoCard(video: vs[i], queue: videos),
          childCount: vs.length,
        ),
      );

  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[];
    if (grouped) {
      for (final g in groupByMonth(videos)) {
        slivers.add(SliverMainAxisGroup(slivers: [
          SliverPersistentHeader(
              pinned: true, delegate: _HeaderDelegate(g.header)),
          SliverPadding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              sliver: _grid(g.videos)),
        ]));
      }
    } else {
      slivers.add(SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          sliver: _grid(videos)));
    }
    return CustomScrollView(slivers: slivers);
  }
}

class _HeaderDelegate extends SliverPersistentHeaderDelegate {
  _HeaderDelegate(this.text);
  final String text;

  @override
  double get minExtent => 40;
  @override
  double get maxExtent => 40;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlaps) =>
      Container(
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        color: Theme.of(context).scaffoldBackgroundColor,
        child: Text(text, style: Theme.of(context).textTheme.titleMedium),
      );

  @override
  bool shouldRebuild(_HeaderDelegate old) => old.text != text;
}

class _VideoCard extends ConsumerWidget {
  const _VideoCard({required this.video, required this.queue});
  final Video video;
  final List<Video> queue;

  Future<void> _play(BuildContext context, WidgetRef ref,
      {required bool resume}) async {
    if (video.missing) return;
    final playable = queue.where((v) => !v.missing).toList();
    final startMs = resume ? resumeStartMs(video) : 0;
    final c = ref.read(playerControllerProvider);
    await c.playList(playable.map((v) => v.path).toList(), video.path,
        start: startMs > 0 ? Duration(milliseconds: startMs) : null);
    if (context.mounted) context.go('/player');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (!video.missing)
          const PopupMenuItem(value: 'play', child: Text('Play from start')),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        PopupMenuItem(
            value: 'show',
            child: Text(Platform.isWindows
                ? 'Show in Explorer'
                : 'Show in Finder')),
        const PopupMenuItem(
            value: 'remove', child: Text('Remove from library')),
      ],
    );
    if (!context.mounted) return;
    switch (choice) {
      case 'play':
        await _play(context, ref, resume: false);
      case 'rename':
        final t = await showDialog<String>(
            context: context, builder: (_) => _RenameDialog(video.title));
        if (t != null && t.trim().isNotEmpty) {
          await ref
              .read(libraryServiceProvider.notifier)
              .rename(video.id, t.trim());
        }
      case 'show':
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,${video.path}']);
        } else if (Platform.isMacOS) {
          await Process.run('open', ['-R', video.path]);
        }
      case 'remove':
        final ok = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Remove from library?'),
            content: Text(
                '"${video.title}" will be removed from Marquee. The video file is not deleted.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Cancel')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Remove')),
            ],
          ),
        );
        if (ok == true) {
          await ref.read(libraryServiceProvider.notifier).removeVideo(video.id);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frac = progressFraction(video);
    final thumb = video.thumbnailPath;
    final card = Opacity(
      opacity: video.missing ? 0.4 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (thumb != null && File(thumb).existsSync())
                    Image.file(File(thumb),
                        fit: BoxFit.cover,
                        key: ValueKey(thumb),
                        errorBuilder: (_, _, _) => const _ThumbFailed())
                  else if (video.durationMs > 0 || video.missing)
                    const _ThumbFailed()
                  else
                    const _Shimmer(),
                  if (video.durationMs > 0)
                    Positioned(
                      right: 6,
                      bottom: frac != null ? 8 : 6,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 5, vertical: 1),
                        decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4)),
                        child: Text(
                            formatSeconds(video.durationMs ~/ 1000),
                            style: const TextStyle(
                                fontSize: 11, color: Colors.white)),
                      ),
                    ),
                  if (frac != null)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: LinearProgressIndicator(
                          value: frac, minHeight: 3),
                    ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(video.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium),
          Text(shortDate(effectiveDate(video).toLocal()),
              style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
    );
    return Tooltip(
      message: video.missing ? 'Drive not connected' : '',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _play(context, ref, resume: true),
        onSecondaryTapUp: (d) => _menu(context, ref, d.globalPosition),
        child: MouseRegion(
          cursor: video.missing
              ? SystemMouseCursors.forbidden
              : SystemMouseCursors.click,
          child: card,
        ),
      ),
    );
  }
}

class _ThumbFailed extends StatelessWidget {
  const _ThumbFailed();
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.movie_outlined, size: 36)),
      );
}

class _Shimmer extends StatefulWidget {
  const _Shimmer();
  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _a = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1200))
    ..repeat(reverse: true);

  @override
  void dispose() {
    _a.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _a,
        builder: (_, _) => ColoredBox(
          color: Color.lerp(const Color(0xFF3A3A3A), const Color(0xFF555555),
              _a.value)!,
        ),
      );
}

class _RenameDialog extends StatefulWidget {
  const _RenameDialog(this.initial);
  final String initial;
  @override
  State<_RenameDialog> createState() => _RenameDialogState();
}

class _RenameDialogState extends State<_RenameDialog> {
  late final _c = TextEditingController(text: widget.initial);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Rename'),
        content: SizedBox(
          width: 360,
          child: TextField(
              controller: _c,
              autofocus: true,
              onSubmitted: (v) => Navigator.pop(context, v)),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          FilledButton(
              onPressed: () => Navigator.pop(context, _c.text),
              child: const Text('Save')),
        ],
      );
}

class _FoldersDialog extends ConsumerWidget {
  const _FoldersDialog();
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final folders = ref.watch(foldersProvider).value ?? const <LibraryFolder>[];
    return AlertDialog(
      title: const Text('Library folders'),
      content: SizedBox(
        width: 520,
        child: folders.isEmpty
            ? const Text('No folders yet.')
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final f in folders)
                    ListTile(
                      dense: true,
                      title: Text(f.path),
                      trailing: IconButton(
                        tooltip: 'Remove folder (files are kept)',
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () => ref
                            .read(libraryServiceProvider.notifier)
                            .removeFolder(f.id),
                      ),
                    ),
                ],
              ),
      ),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close')),
      ],
    );
  }
}
