import 'dart:io';

import 'package:flutter/material.dart';

import '../core/db/database.dart';

/// Thumbnail for [video]: the cached frame, a placeholder if it failed or the
/// drive is gone, or a shimmer while it is still being generated.
class VideoThumb extends StatelessWidget {
  const VideoThumb(this.video, {super.key});
  final Video? video;

  @override
  Widget build(BuildContext context) {
    final v = video;
    if (v == null) return const ThumbFailed();
    final thumb = v.thumbnailPath;
    if (thumb != null && File(thumb).existsSync()) {
      return Image.file(File(thumb),
          fit: BoxFit.cover,
          key: ValueKey(thumb),
          errorBuilder: (_, _, _) => const ThumbFailed());
    }
    if (v.durationMs > 0 || v.missing) return const ThumbFailed();
    return const Shimmer();
  }
}

class ThumbFailed extends StatelessWidget {
  const ThumbFailed({super.key});
  @override
  Widget build(BuildContext context) => ColoredBox(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: const Center(child: Icon(Icons.movie_outlined, size: 36)),
      );
}

class Shimmer extends StatefulWidget {
  const Shimmer({super.key});
  @override
  State<Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<Shimmer>
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
          color: Color.lerp(
              const Color(0xFF3A3A3A), const Color(0xFF555555), _a.value)!,
        ),
      );
}
