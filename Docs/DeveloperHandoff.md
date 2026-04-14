# Tahoe Player Developer Handoff

Date: 2026-04-15

Environment used for this pass:

- macOS 26.4.1
- Xcode 26.4
- Swift 6.3
- SwiftPM GUI app launched as a staged `.app` bundle

## Current Product Scope

Tahoe Player is a local macOS video player with two runtime playback backends:

- AVFoundation for Apple-native formats such as MP4 and MOV
- libmpv for broader containers such as MKV, WebM, AVI, TS, and M2TS

The app still keeps an FFmpeg preparation path for files that stay on the
AVFoundation branch but need a temporary MP4 before `AVPlayer` can open them.

## What Was Built

- Created a SwiftPM executable app named `TahoePlayer`.
- Added `script/build_and_run.sh` so the app builds, stages, signs, and
  launches as a foreground `.app` bundle instead of a raw SwiftPM executable.
- Added a SwiftUI `WindowGroup` app entry point with macOS window placement.
- Added an `AppDelegate` for foreground activation and Finder/Open With file
  events.
- Added a `PlayerStore` as the main observable UI state owner.
- Added `AVFoundationPlaybackEngine` for Apple-native playback.
- Added a `CMpv` system-library target plus `MPVPlaybackEngine` for direct
  libmpv playback.
- Added `MPVPlaybackState` so EOF, replay, pause, and seek behavior stay
  explicit on the libmpv path.
- Added `MediaPreparationService` for:
  - `AVURLAsset.load(.isPlayable)` native compatibility checks
  - FFmpeg remux attempts using video stream copy
  - HEVC MP4 tagging with `hvc1` so AVFoundation accepts copied HEVC video
  - EAC3 and other audio conversion to stereo AAC for reliable Mac playback
  - SRT and other text subtitle conversion to MP4 `mov_text`
  - deterministic temporary output under
    `~/Library/Caches/TahoePlayer/Prepared`
- Added `PlayerSurfaceView`, which switches between an `AVPlayerLayer` surface
  and a libmpv-backed `NSOpenGLView`.
- Added always-visible SwiftUI playback controls for play/pause, seek, mute,
  volume, playback speed, subtitles, and full screen.
- Added `FloatingPlaybackControlsOverlay` so the control panel can be dragged
  without leaking clicks through to the video surface.
- Added double-click full-screen toggling on the video surface and a custom top
  drag region, including restoring from full screen back to the previous
  window.
- Added a SwiftUI empty state, preparing state, error banner, drop target, and
  top toolbar.
- Added a generated `AppIcon.icns` and wired it into the staged app bundle.
- Added `Docs/ManualQA.md` for the floating-control drag and EOF replay checks.
- Added `Docs/LearningPlan.md` with the scoped Apple documentation trail,
  learning topics, code map, questions, and exercises.
- Added `Tests/TahoePlayerTests/MPVPlaybackStateTests.swift` for EOF replay
  coverage.

## Important Files

- `Package.swift`: SwiftPM app definition, test target, and `CMpv`
  system-library target
- `Sources/CMpv/module.modulemap`: module map for `libmpv`
- `Sources/CMpv/shim.h`: exported `mpv` headers
- `Sources/TahoePlayer/App/TahoePlayerApp.swift`: app scene, commands, window
  sizing
- `Sources/TahoePlayer/App/AppDelegate.swift`: foreground activation and file
  open event routing
- `Sources/TahoePlayer/Stores/PlayerStore.swift`: app state, file loading,
  drag/drop, menu actions, backend switching, and playback observation
- `Sources/TahoePlayer/Services/PlaybackEngine.swift`: AVFoundation-facing
  backend contract
- `Sources/TahoePlayer/Services/AVFoundationPlaybackEngine.swift`:
  AVFoundation backend implementation
- `Sources/TahoePlayer/Services/MPVPlaybackEngine.swift`: libmpv playback,
  render context management, subtitle track inspection, and EOF handling
- `Sources/TahoePlayer/Services/MPVPlaybackState.swift`: tiny state machine for
  EOF replay and pause/seek intent
- `Sources/TahoePlayer/Services/MediaPreparationService.swift`: native
  playable checks and FFmpeg preparation for the AVFoundation fallback path
- `Sources/TahoePlayer/Views/ContentView.swift`: main SwiftUI UI and toolbar
- `Sources/TahoePlayer/Views/PlayerSurfaceView.swift`: `AVPlayerLayer` bridge,
  libmpv OpenGL bridge, and double-click full-screen forwarding
- `Sources/TahoePlayer/Views/PlaybackControlsView.swift`: SwiftUI transport,
  mute, volume, speed, subtitle, full-screen controls, and drag handle
- `Sources/TahoePlayer/Views/FloatingPlaybackControlsPanel.swift`: floating
  control placement, drag clamping, and reset behavior
- `Tests/TahoePlayerTests/MPVPlaybackStateTests.swift`: EOF regression tests
- `Docs/ManualQA.md`: manual validation steps for interaction regressions
- `script/build_and_run.sh`: canonical local build/run entrypoint

## Dependencies

Install runtime and build dependencies with:

```bash
brew install mpv ffmpeg
```

`mpv` provides the `libmpv` dylib consumed by the `CMpv` system-library target.
`ffmpeg` is still used by the AVFoundation fallback preparation flow.

Current FFmpeg search paths:

- `/opt/homebrew/bin/ffmpeg`
- `/usr/local/bin/ffmpeg`
- `/opt/local/bin/ffmpeg`
- `/usr/bin/ffmpeg`

If a developer uses a custom FFmpeg location, update
`MediaPreparationService.resolveFFmpeg()`.

## How To Run

```bash
./script/build_and_run.sh
```

Process verification:

```bash
./script/build_and_run.sh --verify
```

The script kills any existing `TahoePlayer` process, runs `swift build`, stages
`dist/TahoePlayer.app`, writes the bundle `Info.plist`, bundles Homebrew dylibs
into the app, signs the result, and launches it with `/usr/bin/open -n`.

## Review Performed

Commands run:

```bash
swift build
swift test
./script/build_and_run.sh --verify
```

Result:

- Build succeeded.
- Tests succeeded.
- App bundle launch succeeded.
- `TahoePlayer` process was verified as running.

Manual verification focus for this pass:

- Floating playback controls:
  - drag handle no longer pauses the video surface underneath
  - handle drag no longer jitters or vibrates in place
  - control buttons remain clickable after a drag
- libmpv EOF replay:
  - `keep-open=yes` stops on the last frame
  - pressing play after EOF now seeks to `0:00` and resumes
  - opening a new libmpv-backed file after EOF does not inherit stale state

See `Docs/ManualQA.md` for the repeatable checklist.

## Visual Review Status

Screenshot-based visual inspection was used during QA.

To do visual QA manually, run:

```bash
screencapture -x /tmp/tahoe-player-qa.png
```

Inspect:

- Empty state alignment
- Toolbar title and compatibility note truncation
- Floating SwiftUI controls: play/pause, timeline, mute, volume, speed,
  subtitle menu, full screen, drag handle, and double-click reset
- Preparing overlay during fallback preparation
- Error banner when FFmpeg is missing or conversion fails
- Full-screen behavior

## Known Limitations

- The libmpv renderer currently uses the OpenGL render API. That keeps the app
  working today, but a Metal-backed surface would be a better long-term fit.
- Only a subset of broad containers is routed straight to libmpv today:
  `avi`, `flv`, `m2ts`, `mkv`, `mts`, `ts`, and `webm`.
- Files that still rely on the FFmpeg fallback may take time and disk space
  because temporary transcoding is expensive.
- No playlist yet.
- No recent files yet.
- Subtitle selection exists on both backends. Audio-track selection is still
  not implemented.
- No sandbox or security-scoped bookmark support yet.
- No automated UI tests yet.
- Regression coverage is still narrow; only EOF replay state is unit-tested.
- Temporary prepared files are cached deterministically but are not pruned yet.
- FFmpeg lookup is hardcoded rather than using a configurable preference.

## Recommended Next Work

1. Add cache cleanup for old prepared MP4 files.
2. Add a recent-files list with security-scoped bookmarks if sandboxing is
   enabled.
3. Add unit tests for formatting, media preparation errors, and `PlayerStore`
   backend transitions.
4. Add audio-track selection across AVFoundation and libmpv.
5. Replace the libmpv OpenGL surface with a Metal or `MTKView` rendering path.
6. Add UI automation for the floating controls drag and click behavior.

## Apple Documentation Used

- SwiftUI App: https://developer.apple.com/documentation/swiftui/app
- SwiftUI Commands: https://developer.apple.com/documentation/swiftui/commands
- Liquid Glass custom views: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- Liquid Glass toolbar grouping: https://developer.apple.com/documentation/swiftui/landmarks-refining-the-system-provided-glass-effect-in-toolbars
- WindowDragGesture: https://developer.apple.com/documentation/swiftui/windowdraggesture
- AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- AVPlayerLayer: https://developer.apple.com/documentation/avfoundation/avplayerlayer
- AVAsset: https://developer.apple.com/documentation/avfoundation/avasset
- AVMediaSelectionGroup: https://developer.apple.com/documentation/avfoundation/avmediaselectiongroup
- NSOpenGLView: https://developer.apple.com/documentation/appkit/nsopenglview
- UTType: https://developer.apple.com/documentation/uniformtypeidentifiers/uttype
