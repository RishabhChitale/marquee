import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../core/player/player_controller.dart';
import '../library/video_browser.dart';

class CollectionDetailScreen extends ConsumerWidget {
  const CollectionDetailScreen({super.key, required this.collectionId});
  final int collectionId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final s = ref
        .watch(collectionSummariesProvider)
        .where((c) => c.collection.id == collectionId)
        .firstOrNull;
    if (s == null) {
      return const Center(child: Text('Collection not found.'));
    }
    final db = ref.read(databaseProvider);
    return VideoBrowser(
      videos: s.videos,
      emptyMessage: 'No videos match.',
      empty: Column(
        children: [
          _Header(title: s.collection.name, subtitle: '0 videos'),
          const Expanded(
              child: Center(
                  child: Text('Empty. Add videos from the Library.'))),
        ],
      ),
      titleBuilder: (context, visible) => Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/collections'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.collection.name,
                  style: Theme.of(context).textTheme.headlineSmall),
              Text(collectionSubtitle(visible),
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ],
      ),
      actionsBuilder: (context, ref, visible) => [
        const SizedBox(width: 8),
        FilledButton.icon(
          onPressed: visible.every((v) => v.missing)
              ? null
              : () async {
                  final p = visible.where((v) => !v.missing).toList();
                  await ref.read(playerControllerProvider).playList(
                      [for (final v in p) v.path], p.first.path);
                  if (context.mounted) context.go('/player');
                },
          icon: const Icon(Icons.play_arrow),
          label: const Text('Play all'),
        ),
      ],
      extraCardActions: [
        CardAction('Remove from collection', (context, ref, v) async {
          await db.removeFromCollection(collectionId, [v.id]);
        }),
        CardAction('Set as cover', (context, ref, v) async {
          await db.setCollectionCover(collectionId, v.id);
        }),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.title, required this.subtitle});
  final String title, subtitle;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 24, 8),
        child: Row(children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back),
            onPressed: () => context.go('/collections'),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(context).textTheme.headlineSmall),
              Text(subtitle, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ]),
      );
}
