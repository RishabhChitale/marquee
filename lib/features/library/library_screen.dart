import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/library/library_logic.dart';
import '../../core/library/library_providers.dart';
import 'video_browser.dart';

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
    final scan = ref.watch(libraryServiceProvider);

    return VideoBrowser(
      videos: all,
      emptyMessage: scan.scanning ? 'Scanning...' : 'No videos match.',
      empty: folders.isEmpty
          ? Center(
              child: FilledButton.icon(
                onPressed: () => _addFolder(ref),
                icon: const Icon(Icons.create_new_folder_outlined),
                label: const Text('Add a folder of home videos'),
              ),
            )
          : null,
      titleBuilder: (context, visible) {
        final totalMs = visible.fold<int>(0, (a, v) => a + v.durationMs);
        final subtitle = scan.scanning
            ? 'Scanning... ${scan.found} videos found'
            : '${visible.length} video${visible.length == 1 ? '' : 's'}'
                '${totalMs > 0 ? ' · ${formatTotalDuration(totalMs)}' : ''}';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Library', style: Theme.of(context).textTheme.headlineSmall),
            Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
          ],
        );
      },
      actionsBuilder: (context, ref, visible) => [
        IconButton(
          tooltip: 'Folders',
          icon: const Icon(Icons.folder_copy_outlined),
          onPressed: () => showDialog<void>(
              context: context, builder: (_) => const _FoldersDialog()),
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
    );
  }
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
