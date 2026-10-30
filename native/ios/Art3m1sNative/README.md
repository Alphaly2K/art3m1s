# Art3m1s Native iOS

This is the replacement SwiftUI iOS application.

The Flutter iOS shell is obsolete:

- `lib/shell/cupertino_shell.dart`

New iOS features and fixes belong in this Xcode project.

## Current scope

- SwiftUI `App` lifecycle
- `TabView` app shell
- `NavigationStack` library, settings, and about pages
- Native game-directory import
- Native library persistence compatible with the existing `game_library`
  UserDefaults key
- Game discovery for `system.ini`, `.hcb`, XP3/TJS, Scene.pck/Gameexe, and base PFS projects
- `art3m1s.json` manifest loading
- Native settings and online-translation configuration
- Profiler summary export and debug-log export
- Dynamic Rust Core loading entry point

The native player runs Artemis, FVP, Kirikiri and Siglus projects with touch
input, audio and lifecycle handling. Artemis, FVP and Siglus support Metal
presentation with RGBA fallback; Kirikiri uses RGBA frames.
Artemis also supports translation and script HTTP requests.
Build with `--krkr` or `--siglus` to include the corresponding optional engine;
the client and core must be built from matching versions.

## Open

```bash
open native/ios/Art3m1sNative/Art3m1sNative.xcodeproj
```

Build without signing:

```bash
xcodebuild \
  -project native/ios/Art3m1sNative/Art3m1sNative.xcodeproj \
  -target Art3m1sNative \
  -sdk iphoneos \
  -configuration Debug \
  CODE_SIGNING_ALLOWED=NO \
  build
```
