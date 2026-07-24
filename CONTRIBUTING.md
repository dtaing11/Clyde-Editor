# Contributing

Thanks for your interest in contributing!

## Setup

1. Install [Flutter](https://flutter.dev) 3.32+ with desktop support.
2. `flutter pub get`
3. `flutter run -d macos` (or your desktop platform)

## Project conventions

- **Architecture:** UI widgets must not import `rive_native` directly,
  except thin render wrappers under `features/editor/widgets` (e.g. the
  viewport). Engine access goes through `lib/src/engine/` and editor state
  through `lib/src/features/editor/state/`.
- **State:** `EditorState` (a `ChangeNotifier`) is the single source of
  truth. Panels read from it and call methods on it, nothing else.
- **Theme:** all colors/dimensions live in `EditorTheme`. No hard-coded
  colors in widgets.
- **Docs:** public classes and members get `///` doc comments.
- **Ownership:** anything holding native Rive resources (`File`,
  `Artboard`, `Animation`) must have a clear `dispose` path.

## Before opening a PR

```sh
flutter analyze   # must be clean
flutter test      # must pass
```

Keep PRs focused. If you plan a large feature (keyframe editing, exporters,
new panels), open an issue first so we can discuss the design.

## Useful references

- [rive-runtime](https://github.com/rive-app/rive-runtime) - the C++ engine,
  also documents the `.riv` object model (animations, keyframes,
  interpolators) we mirror in editor features.
- [rive_native on pub.dev](https://pub.dev/packages/rive_native) - the
  Flutter bindings and painter API used for rendering.
