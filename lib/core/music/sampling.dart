/// Clip length sent to AudD.
const clipLengthMs = 12000;

/// Videos shorter than this are skipped.
const minVideoMs = 8000;

class ClipPlan {
  const ClipPlan(this.offsetMs, this.lengthMs);
  final int offsetMs;
  final int lengthMs;
}

/// Where to cut [clips] (1, 2 or 3) clips from a video of [durationMs]:
/// 1 -> 50%; 2 -> 30% and 70%; 3 -> 15%, 50%, 85%. A clip is 12 s, clamped to
/// the end of the video. Videos under 8 s (or of unknown length) give none.
List<ClipPlan> planClips(int durationMs, int clips) {
  if (durationMs < minVideoMs) return const [];
  final fractions = switch (clips) {
    1 => const [0.5],
    2 => const [0.3, 0.7],
    _ => const [0.15, 0.5, 0.85],
  };
  final out = <ClipPlan>[];
  for (final f in fractions) {
    var start = (durationMs * f).round();
    var len = clipLengthMs;
    if (start + len > durationMs) {
      // Clamp to the end: shift back if there is room, else shorten.
      start = durationMs - len;
      if (start < 0) {
        start = 0;
        len = durationMs;
      }
    }
    out.add(ClipPlan(start, len));
  }
  return out;
}
