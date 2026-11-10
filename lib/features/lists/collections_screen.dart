import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/video_thumb.dart';

class CollectionsScreen extends ConsumerWidget {
  const CollectionsScreen({super.key});

  Future<void> _create(BuildContext context, WidgetRef ref) async {
    final name = await promptName(context,
        title: 'New collection', action: 'Create');
    if (name == null) return;
    final id = await ref.read(databaseProvider).createCollection(name);
    if (context.mounted) context.go('/collections/$id');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset pos,
      CollectionSummary s) async {
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
          title: 'Rename collection', initial: s.collection.name);
      if (n == null) return;
      final ok = await db.renameCollection(s.collection.id, n);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('A collection named "$n" already exists')));
      }
    } else {
      final ok = await confirmDialog(context,
          title: 'Delete collection?',
          message:
              'Delete "${s.collection.name}"? Only the collection is deleted; '
              'your videos stay in the library.',
          action: 'Delete');
      if (ok) await db.deleteCollection(s.collection.id);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cols = ref.watch(collectionSummariesProvider);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
          child: Row(children: [
            Text('Collections',
                style: Theme.of(context).textTheme.headlineSmall),
            const Spacer(),
            FilledButton.icon(
              onPressed: () => _create(context, ref),
              icon: const Icon(Icons.add),
              label: const Text('New collection'),
            ),
          ]),
        ),
        Expanded(
          child: cols.isEmpty
              ? const Center(child: Text('No collections yet.'))
              : GridView.builder(
                  padding: const EdgeInsets.all(24),
                  gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                    maxCrossAxisExtent: 300,
                    mainAxisSpacing: 16,
                    crossAxisSpacing: 16,
                    childAspectRatio: 1.3,
                  ),
                  itemCount: cols.length,
                  itemBuilder: (_, i) {
                    final s = cols[i];
                    return GestureDetector(
                      onTap: () =>
                          context.go('/collections/${s.collection.id}'),
                      onSecondaryTapUp: (d) =>
                          _menu(context, ref, d.globalPosition, s),
                      child: MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: SizedBox.expand(
                                child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: VideoThumb(s.cover)),
                              ),
                            ),
                            const SizedBox(height: 6),
                            Text(s.collection.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: Theme.of(context).textTheme.bodyLarge),
                            Text(collectionSubtitle(s.videos),
                                style: Theme.of(context).textTheme.bodySmall),
                          ],
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
