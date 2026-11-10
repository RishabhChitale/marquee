import 'package:flutter/material.dart';

/// Placeholder grid; the real library arrives in milestone 2.
class LibraryScreen extends StatelessWidget {
  const LibraryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GridView.count(
          padding: const EdgeInsets.all(24),
          crossAxisCount: 6,
          childAspectRatio: 2 / 3,
          mainAxisSpacing: 16,
          crossAxisSpacing: 16,
          children: List.generate(
            12,
            (_) => DecoratedBox(
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const Center(
          child: Text(
            'Library comes in milestone 2',
            style: TextStyle(fontSize: 22),
          ),
        ),
      ],
    );
  }
}
