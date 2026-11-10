import 'dart:io';

import 'package:path/path.dart' as p;

/// Stores the AudD token in `<app support>/audd_token` (mode 600 where the
/// OS supports it). Falls back to `~/.config/marquee/audd_token` when the
/// app file is missing or empty. The token is never logged.
class TokenStore {
  TokenStore({required this.appSupportDir, required this.homeDir});
  final String appSupportDir;
  final String? homeDir;

  File get appFile => File(p.join(appSupportDir, 'audd_token'));
  File? get fallbackFile => homeDir == null
      ? null
      : File(p.join(homeDir!, '.config', 'marquee', 'audd_token'));

  Future<String?> _read(File? f) async {
    if (f == null) return null;
    try {
      if (!await f.exists()) return null;
      final t = (await f.readAsString()).trim();
      return t.isEmpty ? null : t;
    } catch (_) {
      return null;
    }
  }

  Future<String?> read() async =>
      await _read(appFile) ?? await _read(fallbackFile);

  Future<void> save(String token) async {
    await Directory(appSupportDir).create(recursive: true);
    final f = appFile;
    if (!await f.exists()) await f.create();
    await _chmod600(f);
    await f.writeAsString(token.trim());
  }

  /// Deletes only the app-support token file.
  Future<void> remove() async {
    final f = appFile;
    if (await f.exists()) await f.delete();
  }

  Future<void> _chmod600(File f) async {
    if (!Platform.isMacOS && !Platform.isLinux) return;
    try {
      await Process.run('chmod', ['600', f.path]);
    } catch (_) {}
  }
}
