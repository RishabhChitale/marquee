import 'dart:async';

import 'package:flutter/material.dart';
import 'package:media_kit/media_kit.dart';

/// Playback diagnostics, toggled with the I key. Polls mpv twice a second.
class StatsOverlay extends StatefulWidget {
  const StatsOverlay({super.key, required this.player});
  final Player player;

  @override
  State<StatsOverlay> createState() => _StatsOverlayState();
}

class _StatsOverlayState extends State<StatsOverlay> {
  static const _props = <String, String>{
    'Codec': 'video-codec',
    'Size': 'video-params/w', // combined with h below
    'FPS': 'container-fps',
    'Hwdec': 'hwdec-current',
    'Dropped (vo)': 'frame-drop-count',
    'Dropped (decoder)': 'decoder-frame-drop-count',
    'Cache (s)': 'demuxer-cache-duration',
  };

  Timer? _timer;
  Map<String, String> _values = {};

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(milliseconds: 500), (_) => _poll());
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<String> _get(NativePlayer n, String key) async {
    try {
      final v = await n.getProperty(key);
      return v.isEmpty ? '-' : v;
    } catch (_) {
      return '-';
    }
  }

  Future<void> _poll() async {
    final native = widget.player.platform;
    if (native is! NativePlayer) return;
    final out = <String, String>{};
    for (final e in _props.entries) {
      var v = await _get(native, e.value);
      if (e.key == 'Size') {
        final h = await _get(native, 'video-params/h');
        v = '$v x $h';
      } else if (e.key == 'FPS' || e.key == 'Cache (s)') {
        final d = double.tryParse(v);
        if (d != null) v = d.toStringAsFixed(2);
      }
      out[e.key] = v;
    }
    if (mounted) setState(() => _values = out);
  }

  @override
  Widget build(BuildContext context) {
    final lines = _values.entries.map((e) => '${e.key.padRight(18)}${e.value}');
    return IgnorePointer(
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          lines.join('\n'),
          style: const TextStyle(
            color: Colors.white,
            fontFamily: 'Menlo',
            fontFamilyFallback: ['Consolas', 'monospace'],
            fontSize: 12,
            height: 1.3,
          ),
        ),
      ),
    );
  }
}
