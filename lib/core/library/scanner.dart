import 'dart:io';
import 'dart:isolate';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../db/database.dart';
import 'library_logic.dart';
import 'name_parser.dart';

class FoundFile {
  FoundFile(this.path, this.size, this.modified);
  final String path;
  final int size;
  final DateTime modified;
}

/// Recursively lists video files under [root], skipping hidden entries.
/// Pure and synchronous-ish; run it in an isolate for big libraries.
List<FoundFile> walkVideos(String root) {
  final out = <FoundFile>[];
  void walk(Directory dir) {
    List<FileSystemEntity> children;
    try {
      children = dir.listSync(followLinks: false);
    } catch (_) {
      return;
    }
    for (final e in children) {
      final name = p.basename(e.path);
      if (name.startsWith('.')) continue;
      if (e is Directory) {
        walk(e);
      } else if (e is File && isVideoFileName(name)) {
        try {
          final st = e.statSync();
          out.add(FoundFile(e.path, st.size, st.modified));
        } catch (_) {}
      }
    }
  }

  final d = Directory(root);
  if (d.existsSync()) walk(d);
  return out;
}

class LibraryScanner {
  LibraryScanner(this.db, {this.useIsolate = true});
  final AppDatabase db;
  final bool useIsolate;

  /// Scans every library folder. [onProgress] gets the running count of
  /// videos found. Returns the total found. Idempotent.
  Future<int> scanAll({void Function(int found)? onProgress}) async {
    final folders = await db.select(db.libraryFolders).get();
    var total = 0;
    for (final f in folders) {
      total += await scanFolder(f, base: total, onProgress: onProgress);
    }
    return total;
  }

  Future<int> scanFolder(
    LibraryFolder folder, {
    int base = 0,
    void Function(int found)? onProgress,
  }) async {
    final rootExists = Directory(folder.path).existsSync();
    final found = rootExists
        ? (useIsolate
              ? await Isolate.run(() => walkVideos(folder.path))
              : walkVideos(folder.path))
        : <FoundFile>[];

    final existing = {
      for (final v in await (db.select(
        db.videos,
      )..where((t) => t.folderId.equals(folder.id))).get())
        v.path: v,
    };
    // Current people per video as ordered "role:key" strings, to skip no-ops.
    final peopleNow = <int, List<String>>{};
    {
      final names = {for (final x in await db.select(db.people).get()) x.id: x};
      for (final vp in await db.select(db.videoPeople).get()) {
        final person = names[vp.personId];
        if (person == null) continue;
        (peopleNow[vp.videoId] ??= []).add('${vp.role}:${person.nameKey}');
      }
    }
    String sig(ParsedName pn) => ([
      if (pn.creator != null) 'creator:${personKey(pn.creator!)}',
      for (final f in pn.featured) 'featured:${personKey(f)}',
    ]..sort()).join('|');
    final seen = <String>{};
    final now = DateTime.now();
    var n = 0;

    await db.transaction(() async {
      for (final f in found) {
        seen.add(f.path);
        final old = existing[f.path];
        final stem = p.basenameWithoutExtension(f.path);
        final parsed = parseName(stem);
        final genre = deriveGenre(f.path, folder.path);
        if (old == null) {
          final id = await db
              .into(db.videos)
              .insert(
                VideosCompanion.insert(
                  path: f.path,
                  folderId: folder.id,
                  fileName: p.basename(f.path),
                  title: parsed.title,
                  sizeBytes: f.size,
                  fileModifiedAt: f.modified,
                  addedAt: now,
                  genre: Value(genre),
                ),
              );
          await db.setVideoPeople(id, parsed.creator, parsed.featured);
        } else {
          // Derived fields: genre always follows the folder layout; people
          // and title only when the user has not overridden them.
          if (old.genre != genre) {
            await (db.update(db.videos)..where((t) => t.id.equals(old.id)))
                .write(VideosCompanion(genre: Value(genre)));
          }
          if (!old.peopleOverridden) {
            final have = [...(peopleNow[old.id] ?? const <String>[])]..sort();
            if (have.join('|') != sig(parsed)) {
              await db.setVideoPeople(old.id, parsed.creator, parsed.featured);
            }
          }
          if (!old.titleOverridden &&
              old.title == stem &&
              parsed.title != stem) {
            await (db.update(db.videos)..where((t) => t.id.equals(old.id)))
                .write(VideosCompanion(title: Value(parsed.title)));
          }
          final changed =
              old.sizeBytes != f.size ||
              old.fileModifiedAt.millisecondsSinceEpoch !=
                  f.modified.millisecondsSinceEpoch;
          if (changed || old.missing) {
            await (db.update(
              db.videos,
            )..where((t) => t.id.equals(old.id))).write(
              VideosCompanion(
                sizeBytes: Value(f.size),
                fileModifiedAt: Value(f.modified),
                missing: const Value(false),
                // Changed file: re-thumbnail and re-read metadata.
                thumbnailPath: changed
                    ? const Value(null)
                    : const Value.absent(),
                durationMs: changed ? const Value(0) : const Value.absent(),
                recordedAt: changed ? const Value(null) : const Value.absent(),
              ),
            );
          }
        }
        n++;
        if (n % 20 == 0) onProgress?.call(base + n);
      }
      // Files that vanished are flagged, never deleted. If the whole folder is
      // unreachable (drive unplugged) everything in it is flagged missing.
      for (final old in existing.values) {
        if (!seen.contains(old.path) && !old.missing) {
          await (db.update(db.videos)..where((t) => t.id.equals(old.id))).write(
            const VideosCompanion(missing: Value(true)),
          );
        }
      }
    });
    onProgress?.call(base + n);
    return n;
  }
}
