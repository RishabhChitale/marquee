import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/db/database.dart';
import '../../core/library/library_logic.dart';
import '../../core/library/library_providers.dart';
import '../../core/library/lists_logic.dart';
import '../../core/library/lists_providers.dart';
import '../../core/player/player_controller.dart';
import '../../core/player/time_format.dart';
import '../../widgets/dialogs.dart';
import '../../widgets/video_thumb.dart';
import '../../core/library/tags_logic.dart';
import '../lists/add_to_menu.dart';
import 'video_dialogs.dart';

/// An extra entry in a card's right-click menu.
class CardAction {
  const CardAction(this.label, this.run);
  final String label;
  final Future<void> Function(BuildContext context, WidgetRef ref, Video video)
  run;
}

/// THE timeline grid, shared by Library and Collection detail: header row
/// (title, search, sort, actions), month-grouped grid, multi-select with an
/// action bar, card menu and collection chips.
class VideoBrowser extends ConsumerStatefulWidget {
  const VideoBrowser({
    super.key,
    required this.videos,
    required this.titleBuilder,
    this.actionsBuilder,
    this.extraCardActions = const [],
    this.empty,
    this.emptyMessage = 'No videos match.',
  });

  /// Everything this browser may show (before search/sort).
  final List<Video> videos;

  /// Title + subtitle block, given the currently visible (filtered) list.
  final Widget Function(BuildContext context, List<Video> visible) titleBuilder;

  /// Extra toolbar widgets to the right of the sort button.
  final List<Widget> Function(
    BuildContext context,
    WidgetRef ref,
    List<Video> visible,
  )?
  actionsBuilder;

  final List<CardAction> extraCardActions;

  /// Shown instead of the grid when [videos] is empty.
  final Widget? empty;
  final String emptyMessage;

  @override
  ConsumerState<VideoBrowser> createState() => _VideoBrowserState();
}

class _VideoBrowserState extends ConsumerState<VideoBrowser> {
  String _query = '';
  VideoSort _sort = VideoSort.newest;
  String? _genre;
  String? _person;
  Set<int> _selected = {};
  int? _anchor; // index into the visible list

  bool get _mac => Platform.isMacOS;

  List<int> _orderedSelection(List<Video> visible) => [
    for (final v in visible)
      if (_selected.contains(v.id)) v.id,
  ];

  void _clear() => setState(() {
    _selected = {};
    _anchor = null;
  });

  void _selectAll(List<Video> visible) => setState(() {
    _selected = {for (final v in visible) v.id};
    _anchor = visible.isEmpty ? null : 0;
  });

  /// Returns true when the click was consumed as a selection gesture.
  bool _handleClick(List<Video> visible, int index) {
    final kb = HardwareKeyboard.instance;
    final shift = kb.isShiftPressed;
    final mod = _mac ? kb.isMetaPressed : kb.isControlPressed;
    final ids = [for (final v in visible) v.id];
    if (shift && _anchor != null) {
      final range = rangeSelect(ids, _anchor!, index);
      setState(() => _selected = mod ? {..._selected, ...range} : range);
      return true;
    }
    if (mod || shift || _selected.isNotEmpty) {
      final id = ids[index];
      setState(() {
        _selected = {..._selected};
        if (!_selected.remove(id)) _selected.add(id);
        _anchor = index;
      });
      return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final idx = ref.watch(peopleIndexProvider);
    final tagged = applyTagFilter(
      widget.videos,
      idx,
      TagFilter(genre: _genre, personKey: _person),
    );
    final visible = filterAndSort(tagged, _query, _sort);
    final visibleIds = {for (final v in visible) v.id};
    // Drop selections that scrolled out of view or were removed.
    final sel = _selected.intersection(visibleIds);
    if (sel.length != _selected.length) {
      _selected = sel;
      if (sel.isEmpty) _anchor = null;
    }
    final collections = ref.watch(videoCollectionsProvider);

    return CallbackShortcuts(
      bindings: {
        SingleActivator(
          LogicalKeyboardKey.keyA,
          meta: _mac,
          control: !_mac,
        ): () =>
            _selectAll(visible),
        const SingleActivator(LogicalKeyboardKey.escape): _clear,
      },
      child: Focus(
        autofocus: true,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
              child: Row(
                children: [
                  widget.titleBuilder(context, visible),
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
                        onChanged: (v) => setState(() => _query = v),
                      ),
                    ),
                  ),
                  const Spacer(),
                  PopupMenuButton<VideoSort>(
                    tooltip: 'Sort',
                    initialValue: _sort,
                    icon: const Icon(Icons.sort),
                    onSelected: (s) => setState(() => _sort = s),
                    itemBuilder: (_) => [
                      for (final s in VideoSort.values)
                        CheckedPopupMenuItem(
                          value: s,
                          checked: s == _sort,
                          child: Text(s.label),
                        ),
                    ],
                  ),
                  ...?widget.actionsBuilder?.call(context, ref, visible),
                ],
              ),
            ),
            if (widget.videos.isNotEmpty)
              _TagBar(
                genres: genreCounts(widget.videos, idx, _person),
                people: personCounts(widget.videos, idx, _genre),
                genre: _genre,
                person: _person,
                onGenre: (g) => setState(() => _genre = g),
                onPerson: (k) => setState(() => _person = k),
              ),
            Expanded(
              child: widget.videos.isEmpty && widget.empty != null
                  ? widget.empty!
                  : visible.isEmpty
                  ? Center(child: Text(widget.emptyMessage))
                  : _Timeline(
                      videos: visible,
                      grouped: _sort.grouped,
                      selected: _selected,
                      collections: collections,
                      extraActions: widget.extraCardActions,
                      people: idx,
                      onClick: (i) => _handleClick(visible, i),
                      targetsFor: (v) => _selected.contains(v.id)
                          ? _orderedSelection(visible)
                          : [v.id],
                    ),
            ),
            if (_selected.isNotEmpty)
              _ActionBar(
                count: _selected.length,
                onPlaylist: (pos) => showAddToPlaylistMenu(
                  context,
                  ref,
                  pos,
                  _orderedSelection(visible),
                ),
                onCollection: (pos) => showAddToCollectionMenu(
                  context,
                  ref,
                  pos,
                  _orderedSelection(visible),
                ),
                onClear: _clear,
              ),
          ],
        ),
      ),
    );
  }
}

class _TagBar extends StatelessWidget {
  const _TagBar({
    required this.genres,
    required this.people,
    required this.genre,
    required this.person,
    required this.onGenre,
    required this.onPerson,
  });
  final List<TagCount> genres;
  final List<TagCount> people;
  final String? genre;
  final String? person;
  final ValueChanged<String?> onGenre;
  final ValueChanged<String?> onPerson;

  List<TagCount> _withSelected(List<TagCount> l, String? sel) =>
      sel == null || l.any((c) => c.key == sel)
      ? l
      : [...l, TagCount(sel, sel, 0)];

  Widget _row(
    String label,
    List<TagCount> items,
    String? sel,
    ValueChanged<String?> on,
  ) {
    if (items.isEmpty) return const SizedBox.shrink();
    return SizedBox(
      height: 36,
      child: Row(
        children: [
          SizedBox(width: 60, child: Text(label)),
          Expanded(
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final c in items)
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: FilterChip(
                      visualDensity: VisualDensity.compact,
                      label: Text('${c.label} (${c.count})'),
                      selected: sel == c.key,
                      onSelected: (on0) => on(on0 ? c.key : null),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final g = _withSelected(genres, genre);
    final p = _withSelected(people, person);
    if (g.isEmpty && p.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: [
          Expanded(
            child: Column(
              children: [
                _row('Genres', g, genre, onGenre),
                _row('People', p, person, onPerson),
              ],
            ),
          ),
          if (genre != null || person != null)
            TextButton(
              onPressed: () {
                onGenre(null);
                onPerson(null);
              },
              child: const Text('Clear filters'),
            ),
        ],
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  const _ActionBar({
    required this.count,
    required this.onPlaylist,
    required this.onCollection,
    required this.onClear,
  });
  final int count;
  final void Function(Offset) onPlaylist, onCollection;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Material(
    elevation: 8,
    color: Theme.of(context).colorScheme.surfaceContainerHigh,
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
      child: Row(
        children: [
          Text(
            '$count selected',
            style: Theme.of(context).textTheme.titleSmall,
          ),
          const Spacer(),
          Builder(
            builder: (ctx) => TextButton.icon(
              onPressed: () => onPlaylist(anchorBelow(ctx)),
              icon: const Icon(Icons.playlist_add),
              label: const Text('Add to playlist'),
            ),
          ),
          const SizedBox(width: 8),
          Builder(
            builder: (ctx) => TextButton.icon(
              onPressed: () => onCollection(anchorBelow(ctx)),
              icon: const Icon(Icons.create_new_folder_outlined),
              label: const Text('Add to collection'),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(onPressed: onClear, child: const Text('Clear')),
        ],
      ),
    ),
  );
}

class _Timeline extends StatelessWidget {
  const _Timeline({
    required this.videos,
    required this.grouped,
    required this.selected,
    required this.collections,
    required this.extraActions,
    required this.people,
    required this.onClick,
    required this.targetsFor,
  });
  final List<Video> videos;
  final bool grouped;
  final Set<int> selected;
  final Map<int, List<Collection>> collections;
  final List<CardAction> extraActions;
  final PeopleByVideo people;
  final bool Function(int index) onClick;
  final List<int> Function(Video) targetsFor;

  static const _delegate = SliverGridDelegateWithMaxCrossAxisExtent(
    maxCrossAxisExtent: 280,
    mainAxisSpacing: 16,
    crossAxisSpacing: 16,
    childAspectRatio: 1.15,
  );

  SliverGrid _grid(List<Video> vs, int offset) => SliverGrid(
    gridDelegate: _delegate,
    delegate: SliverChildBuilderDelegate((_, i) {
      final v = vs[i];
      return _VideoCard(
        video: v,
        queue: videos,
        selected: selected.contains(v.id),
        collections: collections[v.id] ?? const [],
        extraActions: extraActions,
        people: people[v.id],
        onClick: () => onClick(offset + i),
        targets: () => targetsFor(v),
      );
    }, childCount: vs.length),
  );

  @override
  Widget build(BuildContext context) {
    final slivers = <Widget>[];
    if (grouped) {
      var offset = 0;
      for (final g in groupByMonth(videos)) {
        slivers.add(
          SliverMainAxisGroup(
            slivers: [
              SliverPersistentHeader(
                pinned: true,
                delegate: _HeaderDelegate(g.header),
              ),
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
                sliver: _grid(g.videos, offset),
              ),
            ],
          ),
        );
        offset += g.videos.length;
      }
    } else {
      slivers.add(
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
          sliver: _grid(videos, 0),
        ),
      );
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
  const _VideoCard({
    required this.video,
    required this.queue,
    required this.selected,
    required this.collections,
    required this.extraActions,
    required this.people,
    required this.onClick,
    required this.targets,
  });
  final Video video;
  final List<Video> queue;
  final bool selected;
  final List<Collection> collections;
  final List<CardAction> extraActions;
  final List<PersonRef>? people;
  final bool Function() onClick;
  final List<int> Function() targets;

  Future<void> _play(
    BuildContext context,
    WidgetRef ref, {
    required bool resume,
  }) async {
    if (video.missing) return;
    final playable = queue.where((v) => !v.missing).toList();
    final startMs = resume ? resumeStartMs(video) : 0;
    final c = ref.read(playerControllerProvider);
    await c.playList(
      playable.map((v) => v.path).toList(),
      video.path,
      start: startMs > 0 ? Duration(milliseconds: startMs) : null,
    );
    if (context.mounted) context.go('/player');
  }

  Future<void> _menu(BuildContext context, WidgetRef ref, Offset pos) async {
    final choice = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(pos.dx, pos.dy, pos.dx, pos.dy),
      items: [
        if (!video.missing)
          const PopupMenuItem(value: 'play', child: Text('Play from start')),
        const PopupMenuItem(value: 'playlist', child: Text('Add to playlist')),
        const PopupMenuItem(
          value: 'collection',
          child: Text('Add to collection'),
        ),
        for (var i = 0; i < extraActions.length; i++)
          PopupMenuItem(value: 'x$i', child: Text(extraActions[i].label)),
        const PopupMenuDivider(),
        const PopupMenuItem(value: 'rename', child: Text('Rename')),
        const PopupMenuItem(value: 'people', child: Text('Edit people...')),
        const PopupMenuItem(value: 'details', child: Text('Details...')),
        PopupMenuItem(
          value: 'show',
          child: Text(
            Platform.isWindows ? 'Show in Explorer' : 'Show in Finder',
          ),
        ),
        const PopupMenuItem(
          value: 'remove',
          child: Text('Remove from library'),
        ),
      ],
    );
    if (choice == null || !context.mounted) return;
    if (choice.startsWith('x')) {
      await extraActions[int.parse(choice.substring(1))].run(
        context,
        ref,
        video,
      );
      return;
    }
    switch (choice) {
      case 'play':
        await _play(context, ref, resume: false);
      case 'playlist':
        await showAddToPlaylistMenu(context, ref, pos, targets());
      case 'collection':
        await showAddToCollectionMenu(context, ref, pos, targets());
      case 'rename':
        final t = await promptName(
          context,
          title: 'Rename',
          initial: video.title,
        );
        if (t != null) {
          await ref.read(libraryServiceProvider.notifier).rename(video.id, t);
        }
      case 'people':
        await showEditPeople(context, ref, video);
      case 'details':
        await showDetails(context, ref, video);
      case 'show':
        if (Platform.isWindows) {
          await Process.run('explorer', ['/select,${video.path}']);
        } else if (Platform.isMacOS) {
          await Process.run('open', ['-R', video.path]);
        }
      case 'remove':
        final ok = await confirmDialog(
          context,
          title: 'Remove from library?',
          message:
              '"${video.title}" will be removed from Marquee (and from any '
              'playlists and collections). The video file is not deleted.',
        );
        if (ok) {
          await ref.read(libraryServiceProvider.notifier).removeVideo(video.id);
        }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final frac = progressFraction(video);
    final accent = Theme.of(context).colorScheme.primary;
    final chips = chipSplit(collections);
    final card = Opacity(
      opacity: video.missing ? 0.4 : 1,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Container(
              foregroundDecoration: selected
                  ? BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: accent, width: 2),
                    )
                  : null,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    VideoThumb(video),
                    if (video.durationMs > 0)
                      Positioned(
                        right: 6,
                        bottom: frac != null ? 8 : 6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.black87,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            formatSeconds(video.durationMs ~/ 1000),
                            style: const TextStyle(
                              fontSize: 11,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    if (frac != null)
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: LinearProgressIndicator(
                          value: frac,
                          minHeight: 3,
                        ),
                      ),
                    if (selected)
                      Positioned(
                        left: 6,
                        top: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: accent,
                            shape: BoxShape.circle,
                          ),
                          padding: const EdgeInsets.all(2),
                          child: Icon(
                            Icons.check,
                            size: 16,
                            color: Theme.of(context).colorScheme.onPrimary,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            video.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          if (peopleLine(people) != null)
            Text(
              peopleLine(people)!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          Row(
            children: [
              Text(
                shortDate(effectiveDate(video).toLocal()),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              if (video.sourceDomain != null) ...[
                const SizedBox(width: 8),
                Icon(
                  Icons.public,
                  size: 12,
                  color: Theme.of(context).textTheme.bodySmall?.color,
                ),
                const SizedBox(width: 2),
                Flexible(
                  child: Text(
                    video.sourceDomain!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ],
          ),
          if (chips.shown.isNotEmpty)
            SizedBox(
              height: 22,
              child: Row(
                children: [
                  for (final c in chips.shown)
                    Flexible(
                      child: Padding(
                        padding: const EdgeInsets.only(right: 4, top: 2),
                        child: ActionChip(
                          visualDensity: VisualDensity.compact,
                          padding: EdgeInsets.zero,
                          labelPadding: const EdgeInsets.symmetric(
                            horizontal: 6,
                          ),
                          label: Text(
                            c.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => context.go('/collections/${c.id}'),
                        ),
                      ),
                    ),
                  if (chips.extra > 0)
                    Text(
                      '+${chips.extra}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
    return Tooltip(
      message: video.missing ? 'Drive not connected' : '',
      waitDuration: const Duration(milliseconds: 400),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (!onClick()) _play(context, ref, resume: true);
        },
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
