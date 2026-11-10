import 'dart:async';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:window_manager/window_manager.dart';

import '../../core/player/player_controller.dart';
import '../../core/player/time_format.dart';

class PlayerScreen extends ConsumerStatefulWidget {
  const PlayerScreen({super.key});

  @override
  ConsumerState<PlayerScreen> createState() => _PlayerScreenState();
}

class _PlayerScreenState extends ConsumerState<PlayerScreen> {
  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  final FocusNode _focus = FocusNode();
  Timer? _hideTimer;
  bool _controlsVisible = true;
  bool _fullscreen = false;
  bool _hasMedia = false;
  double _preMuteVolume = 100;

  PlayerController get _c => ref.read(playerControllerProvider);

  @override
  void initState() {
    super.initState();
    _hasMedia = _c.queue.current != null;
    _scheduleHide();
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _focus.dispose();
    super.dispose();
  }

  void _scheduleHide() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) setState(() => _controlsVisible = false);
    });
  }

  void _onMouseMove() {
    if (!_controlsVisible) setState(() => _controlsVisible = true);
    _scheduleHide();
  }

  Future<void> _open(String path) async {
    await _c.open(path);
    if (mounted) setState(() => _hasMedia = true);
  }

  Future<void> _pickFile() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.video);
    final path = result?.files.single.path;
    if (path != null) await _open(path);
  }

  Future<void> _setFullscreen(bool value) async {
    await windowManager.setFullScreen(value);
    if (mounted) setState(() => _fullscreen = value);
  }

  Future<void> _toggleMute() async {
    final p = _c.player;
    if (p.state.volume > 0) {
      _preMuteVolume = p.state.volume;
      await _c.setVolume(0);
    } else {
      await _c.setVolume(_preMuteVolume > 0 ? _preMuteVolume : 100);
    }
  }

  Future<void> _changeVolume(double delta) =>
      _c.setVolume(_c.player.state.volume + delta);

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.space) {
      _c.playOrPause();
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      _c.seekBy(const Duration(seconds: -5));
    } else if (key == LogicalKeyboardKey.arrowRight) {
      _c.seekBy(const Duration(seconds: 5));
    } else if (key == LogicalKeyboardKey.arrowUp) {
      _changeVolume(5);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      _changeVolume(-5);
    } else if (key == LogicalKeyboardKey.keyF) {
      _setFullscreen(!_fullscreen);
    } else if (key == LogicalKeyboardKey.escape) {
      if (_fullscreen) _setFullscreen(false);
    } else if (key == LogicalKeyboardKey.keyM) {
      _toggleMute();
    } else {
      return KeyEventResult.ignored;
    }
    _onMouseMove();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final c = ref.watch(playerControllerProvider);
    return DropTarget(
      onDragDone: (details) {
        if (details.files.isNotEmpty) _open(details.files.first.path);
      },
      child: Focus(
        focusNode: _focus,
        autofocus: true,
        onKeyEvent: _onKey,
        child: MouseRegion(
          onHover: (_) => _onMouseMove(),
          cursor: _controlsVisible || !_hasMedia
              ? MouseCursor.defer
              : SystemMouseCursors.none,
          child: Container(
            color: Colors.black,
            child: _hasMedia
                ? Stack(
                    fit: StackFit.expand,
                    children: [
                      Video(controller: c.video, controls: NoVideoControls),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: IgnorePointer(
                          ignoring: !_controlsVisible,
                          child: AnimatedOpacity(
                            opacity: _controlsVisible ? 1 : 0,
                            duration: const Duration(milliseconds: 200),
                            child: _buildControls(c),
                          ),
                        ),
                      ),
                    ],
                  )
                : _buildEmptyState(),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'Marquee',
            style: TextStyle(
              color: Colors.white,
              fontSize: 40,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drop a video or open a file',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _pickFile,
            icon: const Icon(Icons.folder_open),
            label: const Text('Open file'),
          ),
        ],
      ),
    );
  }

  Widget _buildControls(PlayerController c) {
    final p = c.player;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 12),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black87],
        ),
      ),
      child: IconTheme(
        data: const IconThemeData(color: Colors.white),
        child: DefaultTextStyle(
          style: const TextStyle(color: Colors.white),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _SeekBar(player: p),
              Row(
                children: [
                  StreamBuilder<bool>(
                    stream: p.stream.playing,
                    initialData: p.state.playing,
                    builder: (context, snap) => IconButton(
                      tooltip: 'Play/Pause',
                      icon: Icon(
                        snap.data! ? Icons.pause : Icons.play_arrow,
                      ),
                      onPressed: c.playOrPause,
                    ),
                  ),
                  StreamBuilder<double>(
                    stream: p.stream.volume,
                    initialData: p.state.volume,
                    builder: (context, snap) {
                      final v = snap.data!;
                      return Row(
                        children: [
                          IconButton(
                            tooltip: 'Mute',
                            icon: Icon(
                              v == 0 ? Icons.volume_off : Icons.volume_up,
                            ),
                            onPressed: _toggleMute,
                          ),
                          SizedBox(
                            width: 110,
                            child: Slider(
                              value: v.clamp(0, 100).toDouble(),
                              min: 0,
                              max: 100,
                              onChanged: c.setVolume,
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                  const Spacer(),
                  PopupMenuButton<double>(
                    tooltip: 'Speed',
                    icon: const Icon(Icons.speed),
                    onSelected: c.setRate,
                    itemBuilder: (_) => [
                      for (final s in _speeds)
                        PopupMenuItem(value: s, child: Text('${s}x')),
                    ],
                  ),
                  StreamBuilder<Tracks>(
                    stream: p.stream.tracks,
                    initialData: p.state.tracks,
                    builder: (context, snap) => PopupMenuButton<SubtitleTrack>(
                      tooltip: 'Subtitles',
                      icon: const Icon(Icons.subtitles),
                      onSelected: c.setSubtitleTrack,
                      itemBuilder: (_) => [
                        for (final t in snap.data!.subtitle)
                          PopupMenuItem(
                            value: t,
                            child: Text(_trackLabel(t.id, t.title, t.language)),
                          ),
                      ],
                    ),
                  ),
                  StreamBuilder<Tracks>(
                    stream: p.stream.tracks,
                    initialData: p.state.tracks,
                    builder: (context, snap) => PopupMenuButton<AudioTrack>(
                      tooltip: 'Audio',
                      icon: const Icon(Icons.audiotrack),
                      onSelected: c.setAudioTrack,
                      itemBuilder: (_) => [
                        for (final t in snap.data!.audio)
                          PopupMenuItem(
                            value: t,
                            child: Text(_trackLabel(t.id, t.title, t.language)),
                          ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Fullscreen',
                    icon: Icon(
                      _fullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
                    ),
                    onPressed: () => _setFullscreen(!_fullscreen),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _trackLabel(String id, String? title, String? language) {
    final parts = [
      if (title != null && title.isNotEmpty) title,
      if (language != null && language.isNotEmpty) language,
    ];
    return parts.isEmpty ? id : '${parts.join(' - ')} ($id)';
  }
}

class _SeekBar extends StatefulWidget {
  const _SeekBar({required this.player});

  final Player player;

  @override
  State<_SeekBar> createState() => _SeekBarState();
}

class _SeekBarState extends State<_SeekBar> {
  double? _dragValue;

  @override
  Widget build(BuildContext context) {
    final p = widget.player;
    return StreamBuilder<Duration>(
      stream: p.stream.duration,
      initialData: p.state.duration,
      builder: (context, durSnap) {
        final total = durSnap.data!;
        return StreamBuilder<Duration>(
          stream: p.stream.position,
          initialData: p.state.position,
          builder: (context, posSnap) {
            final maxMs = total.inMilliseconds.toDouble();
            final posMs = _dragValue ?? posSnap.data!.inMilliseconds.toDouble();
            return Row(
              children: [
                Text(formatTime(Duration(milliseconds: posMs.round()))),
                Expanded(
                  child: Slider(
                    value: maxMs <= 0 ? 0 : posMs.clamp(0, maxMs).toDouble(),
                    min: 0,
                    max: maxMs <= 0 ? 1 : maxMs,
                    onChanged: maxMs <= 0
                        ? null
                        : (v) => setState(() => _dragValue = v),
                    onChangeEnd: (v) {
                      p.seek(Duration(milliseconds: v.round()));
                      setState(() => _dragValue = null);
                    },
                  ),
                ),
                Text(formatTime(total)),
              ],
            );
          },
        );
      },
    );
  }
}
