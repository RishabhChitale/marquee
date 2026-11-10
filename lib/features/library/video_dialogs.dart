import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/library_logic.dart';
import '../../core/library/tags_logic.dart';
import '../../core/music/music_providers.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/time_format.dart';

List<String> splitNames(String raw) => [
  for (final n in raw.split(','))
    if (n.trim().isNotEmpty) n.trim(),
];

/// Manual override of creator / featured people. Saved values are never
/// overwritten by rescans.
Future<void> showEditPeople(
  BuildContext context,
  WidgetRef ref,
  Video video,
) async {
  final people = ref.read(peopleIndexProvider)[video.id] ?? const <PersonRef>[];
  final creator = TextEditingController(
    text: people.where((p) => p.isCreator).map((p) => p.name).join(),
  );
  final featured = TextEditingController(
    text: people.where((p) => !p.isCreator).map((p) => p.name).join(', '),
  );
  final svc = ref.read(libraryServiceProvider.notifier);
  final result = await showDialog<String>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Edit people'),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: creator,
              autofocus: true,
              decoration: const InputDecoration(labelText: 'Creator'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: featured,
              decoration: const InputDecoration(
                labelText: 'Featured (comma separated)',
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, 'reset'),
          child: const Text('Reset to file name'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(ctx, 'save'),
          child: const Text('Save'),
        ),
      ],
    ),
  );
  if (result == 'save') {
    final c = creator.text.trim();
    await svc.editPeople(
      video.id,
      c.isEmpty ? null : c,
      splitNames(featured.text),
    );
  } else if (result == 'reset') {
    await svc.resetPeople(video.id);
  }
  creator.dispose();
  featured.dispose();
}

String _size(int b) {
  const u = ['B', 'KB', 'MB', 'GB', 'TB'];
  var v = b.toDouble();
  var i = 0;
  while (v >= 1024 && i < u.length - 1) {
    v /= 1024;
    i++;
  }
  return '${v.toStringAsFixed(i == 0 ? 0 : 1)} ${u[i]}';
}

/// Read-only details. The source URL is selectable text with a copy button;
/// it is never opened automatically.
Future<void> showDetails(BuildContext context, WidgetRef ref, Video v) {
  final people = ref.read(peopleIndexProvider)[v.id] ?? const <PersonRef>[];
  final creator = people.where((p) => p.isCreator).map((p) => p.name);
  final featured = people.where((p) => !p.isCreator).map((p) => p.name);
  final rows = <(String, String)>[
    ('Path', v.path),
    ('Size', _size(v.sizeBytes)),
    ('Duration', v.durationMs > 0 ? formatSeconds(v.durationMs ~/ 1000) : '-'),
    ('Resolution', v.width > 0 ? '${v.width} x ${v.height}' : '-'),
    ('Recorded', effectiveDate(v).toLocal().toString().split('.').first),
    ('Genre', v.genre ?? '-'),
    ('Creator', creator.isEmpty ? '-' : creator.join(', ')),
    ('Featured', featured.isEmpty ? '-' : featured.join(', ')),
  ];
  final matches = ref.read(matchesByVideoProvider)[v.id] ?? const [];
  Future<void> playAt(BuildContext ctx, int offsetMs) async {
    Navigator.pop(ctx);
    if (v.missing) return;
    await ref
        .read(playerControllerProvider)
        .open(v.path, start: Duration(milliseconds: offsetMs));
    if (context.mounted) context.go('/player');
  }

  Widget copyBtn(String label, String? url) => url == null || url.isEmpty
      ? const SizedBox.shrink()
      : TextButton.icon(
          onPressed: () => Clipboard.setData(ClipboardData(text: url)),
          icon: const Icon(Icons.copy, size: 14),
          label: Text('Copy $label link'),
        );

  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(v.title, maxLines: 2, overflow: TextOverflow.ellipsis),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final r in rows)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 90,
                        child: Text(
                          r.$1,
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(child: SelectableText(r.$2)),
                    ],
                  ),
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 90,
                    child: Text(
                      'Source',
                      style: Theme.of(ctx).textTheme.bodySmall,
                    ),
                  ),
                  Expanded(child: SelectableText(v.sourceUrl ?? 'Unknown')),
                  if (v.sourceUrl != null)
                    IconButton(
                      tooltip: 'Copy source URL',
                      icon: const Icon(Icons.copy, size: 18),
                      onPressed: () =>
                          Clipboard.setData(ClipboardData(text: v.sourceUrl!)),
                    ),
                ],
              ),
              if (matches.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text('Music', style: Theme.of(ctx).textTheme.titleSmall),
                for (final m in matches)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextButton(
                          onPressed: () => playAt(ctx, m.offsetMs),
                          child: Text(formatSeconds(m.offsetMs ~/ 1000)),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              SelectableText('${m.artist} - ${m.title}'),
                              Wrap(
                                children: [
                                  copyBtn('song', m.songLink),
                                  copyBtn('Spotify', m.spotifyUrl),
                                  copyBtn('Apple Music', m.appleMusicUrl),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Close'),
        ),
      ],
    ),
  );
}
