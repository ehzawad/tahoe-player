# Tahoe Player Developer Handoff

Date: 2026-04-14

Environment used for this pass:

- macOS 26.4.1
- Xcode 26.4
- Swift 6.3
- SwiftPM GUI app launched as a staged `.app` bundle

## Current Product Scope

Tahoe Player is a bare-minimum but robust local video player for macOS Tahoe.
The current app opens local movie files, plays AVFoundation-compatible files
directly, and prepares unsupported local containers such as MKV into a temporary
MP4 file using FFmpeg.

This is not yet an IINA-class decoder stack. The current backend is native
AVFoundation with an FFmpeg compatibility preparation path. Full broad-format
instant playback should use a secondary renderer such as libmpv/mpv later.

## What Was Built

- Created a SwiftPM executable app named `TahoePlayer`.
- Added `script/build_and_run.sh` so the app builds, stages, and launches as a
  real foreground `.app` bundle instead of a raw SwiftPM executable.
- Added a SwiftUI `WindowGroup` app entry point with macOS window placement.
- Added an `AppDelegate` for foreground activation and Finder/Open With file
  events.
- Added a `PlayerStore` as the main observable UI state owner.
- Added a `PlaybackEngine` protocol so a future libmpv/VLCKit backend can be
  introduced without rewiring the whole SwiftUI layer.
- Added `AVFoundationPlaybackEngine` for the first backend.
- Added `MediaPreparationService` for:
  - `AVURLAsset.load(.isPlayable)` native compatibility checks.
  - FFmpeg remux attempt using video stream copy.
  - HEVC MP4 tagging with `hvc1` so AVFoundation accepts copied HEVC video.
  - EAC3/other audio conversion to stereo AAC for reliable Mac playback.
  - SRT/text subtitle conversion to MP4 `mov_text` subtitles.
  - Deterministic temporary output under
    `~/Library/Caches/TahoePlayer/Prepared`.
- Added `PlayerSurfaceView`, an `NSViewRepresentable` wrapper around
  `AVPlayerLayer`.
- Added always-visible SwiftUI playback controls for play/pause, seek, mute,
  volume, playback speed, subtitles, and full screen.
- Added double-click full-screen toggling on the video surface and custom top
  drag region, including restoring from full screen back to the previous window.
- Added a SwiftUI empty state, preparing state, error banner, drop target, and
  top toolbar.
- Added a generated `AppIcon.icns` and wired it into the staged app bundle.
- Added `Docs/LearningPlan.md` with the scoped Apple documentation trail,
  learning topics, code map, questions, and exercises.
- Added `README.md` with run instructions and format support notes.

## Important Files

- `Package.swift`: SwiftPM app definition, targeting macOS 26.
- `Sources/TahoePlayer/App/TahoePlayerApp.swift`: app scene, commands, window
  sizing.
- `Sources/TahoePlayer/App/AppDelegate.swift`: foreground activation and file
  open event routing.
- `Sources/TahoePlayer/Stores/PlayerStore.swift`: app state, file loading,
  drag/drop, menu actions, player observation.
- `Sources/TahoePlayer/Services/PlaybackEngine.swift`: playback backend
  protocol.
- `Sources/TahoePlayer/Services/AVFoundationPlaybackEngine.swift`:
  AVFoundation backend implementation.
- `Sources/TahoePlayer/Services/MediaPreparationService.swift`: native
  playable checks and FFmpeg preparation.
- `Sources/TahoePlayer/Views/ContentView.swift`: main SwiftUI UI and toolbar.
- `Sources/TahoePlayer/Views/PlayerSurfaceView.swift`: `AVPlayerLayer`
  AppKit bridge and double-click full-screen forwarding.
- `Sources/TahoePlayer/Views/PlaybackControlsView.swift`: SwiftUI transport,
  mute, volume, speed, subtitle, and full-screen controls.
- `Resources/AppIcon.icns`: bundled macOS app icon.
- `script/generate_app_icon.swift`: deterministic icon generator.
- `script/build_and_run.sh`: canonical local build/run entrypoint.

## How To Run

```bash
./script/build_and_run.sh
```

Process verification:

```bash
./script/build_and_run.sh --verify
```

The script kills any existing `TahoePlayer` process, runs `swift build`, stages
`dist/TahoePlayer.app`, writes the bundle `Info.plist`, and launches the bundle
with `/usr/bin/open -n`.

## FFmpeg Requirement

FFmpeg is required only when AVFoundation cannot open the original file.

Install it with:

```bash
brew install ffmpeg
```

Current search paths:

- `/opt/homebrew/bin/ffmpeg`
- `/usr/local/bin/ffmpeg`
- `/opt/local/bin/ffmpeg`
- `/usr/bin/ffmpeg`

If a developer uses a custom FFmpeg location, update
`MediaPreparationService.resolveFFmpeg()`.

## Review Performed

Commands run:

```bash
swift build
./script/build_and_run.sh --verify
```

Result:

- Build succeeded.
- App bundle launch succeeded.
- `TahoePlayer` process was verified as running.

Media path verification:

- Generated a short MP4 test file with FFmpeg.
- Generated a short MKV test file with FFmpeg.
- Opened MP4 through the app bundle.
- Opened MKV through the app bundle.
- Confirmed MKV produced one prepared MP4 file in
  `~/Library/Caches/TahoePlayer/Prepared`.
- Confirmed native AVFoundation results:
  - sample MP4: playable, 3.0 seconds.
  - sample MKV: not playable directly.
  - prepared MP4 from MKV: playable, 3.0 seconds.

## Review Fix Applied

The original UI used native `AVPlayerView` floating controls. Those controls
were hard to keep visible and made menu/state sync fragile.

During review, `AVFoundationPlaybackEngine` still kept its own separate
`isPlaying` boolean. That could make the menu or spacebar toggle disagree with
the player.

Fix applied:

- Removed the separate engine-owned play state.
- Made `AVFoundationPlaybackEngine.isPlaying` derive from
  `avPlayer.timeControlStatus == .playing`.
- Replaced `AVPlayerView` with an `AVPlayerLayer` surface and SwiftUI-owned
  controls.
- Added a subtitle menu driven by AVFoundation legible media selection groups.
- Hid the empty open-file state while MKV preparation is in progress.
- Compactified the preparation HUD so it no longer expands to the full filename.

This keeps the visible controls, command menu, and player state aligned.

## MKV QA Fix Pass

User repro file:

```text
/Users/ehz/Downloads/www.UIndex.org    -    Ready Or Not 2 Here I Come 2026 1080p WEB-DL HEVC x265 10Bit DDP5 1 Subs KINGDOM/Ready Or Not 2 Here I Come 2026 1080p WEB-DL HEVC x265 10Bit DDP5 1 Subs KINGDOM.mkv
```

Problems seen before the fix:

- Fragmented MP4 streaming only played the first few seconds, then went black.
- The MKV video appeared before audio was usable.
- The controls were not reliably visible.
- The preparation overlay covered the empty-state card with a huge filename.
- Built-in MKV subtitles were not exposed.

Current FFmpeg preparation behavior:

```bash
ffmpeg -i input.mkv \
  -map 0:v:0 -map 0:a? [-map 0:<text-subtitle-stream> | -sn] \
  -c:v copy -tag:v hvc1 \
  -c:a aac -b:a 192k -ac 2 \
  [-c:s mov_text] \
  -movflags +faststart output-prepared.mp4
```

Post-review hardening:

- Text subtitles are detected with ffprobe before mapping. SRT/ASS/SSA/WebVTT
  style subtitles are converted to `mov_text`; bitmap subtitles such as PGS or
  VobSub are omitted with `-sn` instead of breaking fallback transcode.
- If ffprobe cannot identify the primary video codec, remux first tries the
  HEVC-safe `hvc1` tag and then retries without it. This preserves the fast
  HEVC path without forcing full transcode on probe failure.
- Full-screen shortcut follows macOS convention: Control-Command-F.
- `AVPlayerLayer` resize disables implicit Core Animation actions to avoid
  rubber-banding during live window resize.
- Error banners now animate with the same transition context as media/preparing
  state.
- The generated bundle no longer declares the private IINA-specific MKV UTI.

Full-file prepared output verified:

```text
codec_name=hevc, codec_type=video
codec_name=aac, codec_type=audio, channels=2, channel_layout=stereo
codec_name=mov_text, codec_type=subtitle, language=eng
duration=6471.104000
size=5178514108
```

AVFoundation verification on the prepared full file:

```text
playable=true
duration=6471.083
subtitleCount=2
English | English Forced
```

Visual QA:

- `swift build` succeeds.
- `./script/build_and_run.sh /tmp/tahoe-ready-subtitle-sample.mkv` plays a
  short MKV cut from the repro file with video, stereo AAC audio, and subtitle
  menu.
- User confirmed the short MKV with subtitles worked.
- `./script/build_and_run.sh "<full repro path>"` prepares and plays the full
  MKV.
- User confirmed the full file is working.
- Screenshot inspection confirmed visible controls, sane window size, and a
  subtitle menu on the full file.

## Visual Review Status

Screenshot-based visual inspection was used during QA.

To do visual QA manually, run:

```bash
screencapture -x /tmp/tahoe-player-qa.png
```

Inspect:

- Empty state alignment.
- Toolbar title and compatibility note truncation.
- SwiftUI controls: play/pause, timeline, mute, volume, speed, subtitle menu,
  full screen, and double-click full-screen restore.
- Preparing overlay during MKV conversion.
- Error banner when FFmpeg is missing or conversion fails.
- Full-screen behavior.

## Known Limitations

- MKV support is not native playback. It is prepare-then-play.
- Large MKV files may take time and disk space because fallback transcoding can
  be expensive.
- No playlist yet.
- No recent files yet.
- Subtitle selection exists for AVFoundation legible media groups. Audio-track
  selection is still not implemented.
- No sandbox/security-scoped bookmark support yet.
- No automated UI tests yet.
- No unit tests yet.
- Temporary prepared files are cached deterministically but are not pruned yet.
- FFmpeg lookup is hardcoded rather than using a configurable preference.

## Recommended Next Work

1. Add cache cleanup for old prepared MP4 files.
2. Add a recent-files list with security-scoped bookmarks if sandboxing is
   enabled.
3. Add unit tests for formatting and media preparation error handling.
4. Add audio-track selection from AVFoundation audible media selection groups.
5. Decide whether the long-term backend should be libmpv for instant broad MKV
   playback without prepare-then-play.
6. If libmpv is selected, implement it behind `PlaybackEngine` instead of
   spreading backend conditionals through SwiftUI views.

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
- UTType: https://developer.apple.com/documentation/uniformtypeidentifiers/uttype
