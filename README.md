# Marquee

A cross-platform (macOS + Windows) video player and library app.
A desktop player and library for your own home videos (macOS + Windows). Everything is local and offline: no network calls, no internet metadata. Video files are never modified or deleted ("Remove from library" only drops the database row).

Smart organizing (milestone 4), all derived from local files:
- Creator / featured people from file names such as `Beach day (Mom, Dad).mp4`, editable via right-click "Edit people..." (manual edits are never overwritten by rescans).
- Genre from the top-level subfolder inside a library folder.
- Genre and People tag bar with counts and a "Clear filters" button.
- Download source (website) read from the browser's download attribute (`com.apple.metadata:kMDItemWhereFroms` on macOS via `/usr/bin/xattr` + `/usr/bin/plutil`, `Zone.Identifier` on Windows) and from container tags. Shown under "Details..." as copyable text; never opened automatically.

**macOS sandbox is off.** This is a personal, unsigned app; the sandbox blocked re-reading saved library folders after relaunch and reading the download attribute.

## Stack

- Flutter (stable, Dart 3), desktop
- media_kit (libmpv) for playback
- flutter_riverpod (state), go_router (routing)
- drift + sqlite3_flutter_libs (storage, used from milestone 2)
- window_manager, desktop_drop, file_picker

## Shortcuts

Space play/pause, Left/Right seek 5 s, Up/Down volume 5%, F fullscreen, Esc exit fullscreen, M mute.

## CI builds

Native builds are not done locally. `.github/workflows/build.yml` runs on push to `main` and on manual dispatch:

1. `analyze-test` (ubuntu): `flutter analyze` and `flutter test`
2. `macos`: `flutter build macos --release`, zipped with `ditto` into artifact `marquee-macos`
3. `windows`: `flutter build windows --release`, zipped into artifact `marquee-windows`

Builds are unsigned. Download artifacts from the workflow run's page.

## Opening the unsigned Mac app

Unzip, then either right-click `Marquee.app` > Open, or run:

```
xattr -dr com.apple.quarantine Marquee.app
```
