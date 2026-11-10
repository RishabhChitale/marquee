import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/db/database.dart';
import '../../core/music/music_providers.dart';
import '../../core/music/sampling.dart';
import '../../core/music/scan_engine.dart';

const _noTokenMsg = 'Add an AudD token in Settings';

/// Manual, opt-in music scan: token check, confirm dialog, then the scan.
/// Nothing is sent unless the user presses "Send".
Future<void> startMusicScan(
  BuildContext context,
  WidgetRef ref,
  List<Video> videos,
) async {
  final messenger = ScaffoldMessenger.of(context);
  final token = ref.read(auddTokenProvider).value;
  if (token == null || token.isEmpty) {
    messenger.showSnackBar(const SnackBar(content: Text(_noTokenMsg)));
    return;
  }
  if (ref.read(musicScanProvider).active) {
    messenger.showSnackBar(
      const SnackBar(content: Text('A music scan is already running')),
    );
    return;
  }
  final clips = ref.read(clipCountProvider).value ?? 3;
  final usable = [for (final v in videos) if (!v.missing) v];
  final rescan = await showDialog<bool?>(
    context: context,
    builder: (ctx) => _ConfirmScan(videos: usable, clips: clips),
  );
  if (rescan == null) return;
  await ref
      .read(musicScanProvider.notifier)
      .start(usable, token: token, clipCount: clips, rescan: rescan);
}

class _ConfirmScan extends StatefulWidget {
  const _ConfirmScan({required this.videos, required this.clips});
  final List<Video> videos;
  final int clips;

  @override
  State<_ConfirmScan> createState() => _ConfirmScanState();
}

class _ConfirmScanState extends State<_ConfirmScan> {
  bool _rescan = false;

  @override
  Widget build(BuildContext context) {
    var n = 0;
    var m = 0;
    for (final v in widget.videos) {
      if (!_rescan && v.musicScannedAt != null) continue;
      final c = planClips(v.durationMs, widget.clips).length;
      if (c > 0) {
        n += c;
        m++;
      }
    }
    return AlertDialog(
      title: const Text('Scan music'),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Send $n audio clips (12 s each) from $m videos to AudD for '
              'recognition? Only audio is sent.',
            ),
            const SizedBox(height: 8),
            Text(
              'AudD bills per request.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _rescan,
              onChanged: (v) => setState(() => _rescan = v ?? false),
              title: const Text('Rescan videos already scanned'),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: n == 0 ? null : () => Navigator.pop(context, _rescan),
          child: const Text('Send'),
        ),
      ],
    );
  }
}

/// Header strip: "Recognizing music... 34/120" with Pause and Cancel, or the
/// final / error message once the scan ends.
class MusicProgressBar extends ConsumerWidget {
  const MusicProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pr = ref.watch(musicScanProvider).progress;
    if (pr == null || pr.phase == ScanPhase.idle) {
      return const SizedBox.shrink();
    }
    final ctl = ref.read(musicScanProvider.notifier);
    final live = pr.phase == ScanPhase.running || pr.phase == ScanPhase.paused;
    final paused = pr.phase == ScanPhase.paused;
    final String text;
    if (live) {
      text = '${paused ? 'Paused' : 'Recognizing music...'} '
          '${pr.done}/${pr.total}';
    } else if (pr.phase == ScanPhase.stopped) {
      text = 'Music scan stopped: ${pr.error ?? 'error'} '
          '(${pr.done}/${pr.total})';
    } else if (pr.phase == ScanPhase.cancelled) {
      text = 'Music scan cancelled (${pr.done}/${pr.total})';
    } else {
      text = 'Music scan finished (${pr.done}/${pr.total})';
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
      child: Row(
        children: [
          const Icon(Icons.music_note, size: 18),
          const SizedBox(width: 8),
          Flexible(child: Text(text)),
          const SizedBox(width: 12),
          if (live) ...[
            SizedBox(
              width: 160,
              child: LinearProgressIndicator(
                value: pr.total == 0 ? null : pr.done / pr.total,
              ),
            ),
            TextButton(
              onPressed: paused ? ctl.resume : ctl.pause,
              child: Text(paused ? 'Resume' : 'Pause'),
            ),
            TextButton(onPressed: ctl.cancel, child: const Text('Cancel')),
          ] else
            TextButton(onPressed: ctl.dismiss, child: const Text('Dismiss')),
        ],
      ),
    );
  }
}
