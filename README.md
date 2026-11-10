# Marquee

A cross-platform (macOS + Windows) video player and library app.
Milestone 1: the player (open/drag-drop, controls, shortcuts). The library arrives in milestone 2.

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
