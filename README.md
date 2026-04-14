# Tahoe Player

Tahoe Player is a focused macOS 26 (Tahoe) SwiftUI video player for local
files. It uses AVFoundation for Apple-native formats, libmpv for broader
container coverage, and keeps an FFmpeg preparation path for AVFoundation
fallback cases that still need a temporary MP4.

## Requirements

```bash
brew install mpv ffmpeg
```

## Run

```bash
./script/build_and_run.sh
```

## Test

```bash
swift test
```

## Format Support

- MP4/MOV: opened directly with `AVPlayer`.
- MKV/WebM/AVI/TS/M2TS/FLV: opened directly with libmpv, without
  pre-conversion.
- Files that stay on the AVFoundation path but fail native playback can still
  be prepared into a cached MP4 under
  `~/Library/Caches/TahoePlayer/Prepared`.
- Subtitle handling differs by backend:
  - libmpv reads embedded subtitle tracks directly.
  - the FFmpeg fallback converts text subtitles to MP4 `mov_text` for
    AVFoundation playback.
- The floating playback controls can be dragged by the handle and reset with a
  double-click on that handle.

## Project Shape

- `Sources/TahoePlayer/App`: app entry point, commands, AppDelegate.
- `Sources/TahoePlayer/Stores`: playback state and actions.
- `Sources/TahoePlayer/Services`: AVFoundation playback, libmpv playback, media
  preparation, and EOF replay state handling.
- `Sources/TahoePlayer/Views`: AVPlayerLayer/libmpv surfaces plus draggable
  SwiftUI playback controls, subtitle menu, and full-screen handling.
- `Tests/TahoePlayerTests`: regression coverage for libmpv EOF replay state.
- `Resources/AppIcon.icns`: bundled macOS app icon.
- `script/generate_app_icon.swift`: deterministic icon generator.
- `Docs/ManualQA.md`: manual checks for floating-control drag behavior and EOF
  replay.
- `Docs/LearningPlan.md`: scoped Apple-docs learning plan and practice
  problems.
