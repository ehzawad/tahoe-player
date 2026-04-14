# Tahoe Player

Tahoe Player is a focused macOS 26.4 SwiftUI video player for local files. It
uses native AVFoundation playback for MP4/MOV and prepares unsupported local
containers such as MKV into temporary MP4 files with FFmpeg.

## Run

```bash
./script/build_and_run.sh
```

## Format Support

- MP4/MOV: opened directly with `AVPlayer`.
- MKV/WebM/AVI: accepted by the file picker; if AVFoundation rejects the file,
  the app uses FFmpeg to prepare a cached MP4 copy in
  `~/Library/Caches/TahoePlayer/Prepared`.
- Built-in text subtitles from MKV files are converted to MP4 `mov_text` and
  exposed through the subtitle menu.
- EAC3/other audio is converted to stereo AAC for reliable AVFoundation output.

Install FFmpeg for non-native local formats:

```bash
brew install ffmpeg
```

This is intentionally a first robust version, not an IINA-scale engine. The next
step for full format coverage is replacing the FFmpeg preparation path with an
embedded mpv/libmpv renderer.

## Project Shape

- `Sources/TahoePlayer/App`: app entry point, commands, AppDelegate.
- `Sources/TahoePlayer/Stores`: playback state and actions.
- `Sources/TahoePlayer/Services`: media compatibility and preparation.
- `Sources/TahoePlayer/Views`: AVPlayerLayer surface and SwiftUI controls/layout,
  including double-click full-screen restore, mute, volume, speed, and subtitle
  controls.
- `Resources/AppIcon.icns`: bundled macOS app icon.
- `script/generate_app_icon.swift`: deterministic icon generator.
- `Docs/LearningPlan.md`: scoped Apple-docs learning plan and practice problems.
