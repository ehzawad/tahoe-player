# macOS Tahoe Media Player — Learning Plan

Scoped to this app: a local-file macOS video player with SwiftUI,
AVPlayerLayer rendering for AVFoundation, a libmpv OpenGL surface for broad
containers, draggable SwiftUI playback controls, Liquid Glass on
navigation/control surfaces, and an FFmpeg fallback for files that still need an
AVFoundation-compatible temporary MP4.

No timeline. Just dependency order and the concepts each stage requires.

---

## Apple Documentation Trail

- macOS app pathway: https://developer.apple.com/tutorials/develop-in-swift/build-apps-for-macos
- SwiftUI app structure: https://developer.apple.com/documentation/swiftui/app
- SwiftUI windows/commands: https://developer.apple.com/documentation/swiftui/commands
- AVFoundation overview: https://developer.apple.com/documentation/avfoundation
- AVPlayer: https://developer.apple.com/documentation/avfoundation/avplayer
- AVPlayerLayer: https://developer.apple.com/documentation/avfoundation/avplayerlayer
- AVAsset loading: https://developer.apple.com/documentation/avfoundation/avasset
- AVMediaSelectionGroup: https://developer.apple.com/documentation/avfoundation/avmediaselectiongroup
- Uniform Type Identifiers: https://developer.apple.com/documentation/uniformtypeidentifiers/uttype
- NSViewRepresentable: https://developer.apple.com/documentation/swiftui/nsviewrepresentable
- NSOpenGLView: https://developer.apple.com/documentation/appkit/nsopenglview
- Liquid Glass overview: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- WindowDragGesture: https://developer.apple.com/documentation/swiftui/windowdraggesture

---

## Part A: Platform Core

### Concepts
- A real Mac app is built around windows, menus, toolbars, keyboard commands,
  file access, and full-screen behavior.
- `WindowGroup` is the scene type for document-like windows.
- `Commands` adds native menu-bar items with keyboard shortcuts.
- `@NSApplicationDelegateAdaptor` bridges AppKit lifecycle events such as Dock
  activation and Finder open-file into a SwiftUI app.

### Where this lives in the code
- `TahoePlayerApp.swift` — scene, commands, window placement
- `AppDelegate.swift` — foreground activation, Finder open-file handling

### Apple doc links
- SwiftUI App protocol, `WindowGroup`, `Commands`
- `NSApplicationDelegate`

### Checkpoint questions
1. Why is `WindowGroup` the right starting point for this app?
2. Why bother with menu commands before any media feature exists?
3. What does `AppDelegate.attach(playerStore:)` solve that pure SwiftUI
   lifecycle cannot?

---

## Part B: Media Core

### Concepts
There are two playback stacks in this app today.

AVFoundation path:

    URL -> AVAsset -> AVPlayerItem -> AVPlayer -> AVPlayerLayer

libmpv path:

    URL -> libmpv core -> render context -> NSOpenGLView

- AVFoundation models the media; the player item models the timed presentation;
  the player controls transport and track selection.
- libmpv handles broad-format decoding and exposes track state through the mpv
  property and event API.
- `PlayerSurfaceView` selects the rendering bridge:
  - `AVPlayerLayer` for the AVFoundation path
  - `NSOpenGLView` for the libmpv path
- The SwiftUI controls provide play/pause, scrubber, mute, volume, speed,
  subtitle selection, full-screen actions, and a draggable handle on a compact
  overlay.
- `PlaybackEngine` is currently the AVFoundation-facing abstraction. The libmpv
  path is still owned directly by `PlayerStore` because it needs a different
  rendering surface and event loop.

### Where this lives in the code
- `PlaybackEngine.swift` — AVFoundation-facing backend contract
- `AVFoundationPlaybackEngine.swift` — concrete AVFoundation implementation
- `MPVPlaybackEngine.swift` — libmpv wrapper, subtitle inspection, event handling
- `MPVPlaybackState.swift` — EOF replay and paused-state bookkeeping
- `PlayerSurfaceView.swift` — rendering bridge for both backends
- `FloatingPlaybackControlsPanel.swift` — drag clamping and reset logic
- `PlayerStore.swift` — observable state, owns both backends, syncs
  AVFoundation via KVO and polls libmpv state

### Apple doc links
- AVPlayerLayer, AVPlayer, AVPlayerItem, AVURLAsset
- AVMediaSelectionGroup, AVMediaSelectionOption
- NSViewRepresentable
- NSOpenGLView

### Checkpoint questions
1. Can you explain the difference between `AVAsset`, `AVPlayerItem`,
   `AVPlayer`, and `AVPlayerLayer` without hand-waving?
2. What information comes from mpv properties and events instead of KVO?
3. Why did this app choose SwiftUI-owned controls instead of native AVKit
   controls?
4. Why is `PlaybackEngine` only part of the architecture today instead of the
   complete backend boundary?
5. How does the KVO observer on `timeControlStatus` keep the menu's Play/Pause
   label correct on the AVFoundation path?

---

## Part C: File Opening & Format Boundary

### Concepts
- `NSOpenPanel` is the AppKit file picker. `fileImporter` is the SwiftUI-native
  equivalent preferred for sandboxed apps.
- `UTType` defines what files the picker shows. That is broader than what
  AVFoundation can actually decode.
- `PlayerStore` makes the first backend choice:
  - broad containers such as MKV/WebM/AVI/TS/M2TS/FLV go straight to libmpv
  - Apple-native paths stay on AVFoundation first
- `AVURLAsset.load(.isPlayable)` is still the runtime gate for the
  AVFoundation branch.
- `MediaPreparationService` falls back to FFmpeg remux or transcode only when
  the AVFoundation branch still cannot play the file directly.
- Subtitle handling differs by backend:
  - libmpv reads subtitle tracks directly from the source file
  - the FFmpeg fallback converts text subtitles to MP4 `mov_text` for
    AVFoundation

### Where this lives in the code
- `PlayerStore.presentOpenPanel()` — file picker
- `PlayerStore.handleDrop(_:)` — drag & drop
- `MediaPreparationService.swift` — AVFoundation probe and FFmpeg fallback
- `MPVPlaybackEngine.swift` — direct-playback path for broad containers
- `MediaFile.swift` — model tracking source vs playback URL

### Apple doc links
- NSOpenPanel, `fileImporter`, `UTType`
- `AVURLAsset`, `AVAsset.load(.isPlayable)`
- App Sandbox file access

### Checkpoint questions
1. Why can a file conform to `public.movie` but still fail
   `AVURLAsset.load(.isPlayable)`?
2. What exactly is supported here: a file extension, a container, the codecs
   inside it, or the backend's runtime capability?
3. Why does this app short-circuit MKV/WebM/AVI-style files to libmpv instead
   of trusting AVFoundation's probe?
4. What should happen if FFmpeg is missing and the user opens a file that is
   still on the AVFoundation fallback path?
5. How should the player behave when a new file is opened while another file is
   playing?

---

## Part D: Tahoe Design

### Concepts
- Liquid Glass is not a license to smear translucent effects everywhere.
  Standard SwiftUI and AppKit controls pick up the new material automatically.
- Glass belongs on the navigation and control layer, never on the video content
  layer.
- The app uses `.glassEffect()` on the empty-state card, preparing overlay, and
  error banner. The playback controls use a compact custom panel so the drag
  behavior stays predictable.
- Test with Reduced Transparency and Increased Contrast enabled in macOS
  accessibility settings.

### Where this lives in the code
- `ContentView.swift` — empty state, preparing overlay, error banner
- `PlaybackControlsView.swift` — compact playback control panel
- `FloatingPlaybackControlsPanel.swift` — movable overlay behavior

### Checkpoint questions
1. Where should glass exist in this app, and where should it not?
2. Why is the draggable control surface implemented as a custom overlay instead
   of a system media chrome?
3. What happens to glass effects when the user enables Reduced Transparency?

---

## Code Map

```
Sources/TahoePlayer/
├── App/
│   ├── TahoePlayerApp.swift                — scene, commands, window sizing
│   └── AppDelegate.swift                   — Dock activation, Finder open-file
├── Stores/
│   └── PlayerStore.swift                   — @Observable state, owns both backends
├── Services/
│   ├── PlaybackEngine.swift                — AVFoundation-facing backend contract
│   ├── AVFoundationPlaybackEngine.swift    — AVPlayer + MediaPreparationService
│   ├── MPVPlaybackEngine.swift             — libmpv playback + event/render handling
│   ├── MPVPlaybackState.swift              — EOF replay state
│   └── MediaPreparationService.swift       — isPlayable check, FFmpeg fallback
├── Models/
│   └── MediaFile.swift                     — source/playback URL, title, compat note
├── Views/
│   ├── ContentView.swift                   — player surface, toolbar, overlays, drop
│   ├── PlaybackControlsView.swift          — transport, mute, volume, speed, subtitles
│   ├── FloatingPlaybackControlsPanel.swift — floating overlay positioning
│   └── PlayerSurfaceView.swift             — AVPlayerLayer/libmpv bridge, double-click
└── Support/
    └── Formatters.swift                    — time string formatting

Tests/TahoePlayerTests/
└── MPVPlaybackStateTests.swift             — EOF replay regression coverage
```

---

## Coding Exercises

1. Add `J` / `L` shortcut pair for skip back and forward.
2. Add a recent-files menu using `@AppStorage` and security-scoped bookmarks.
3. Add an audio track selector that works across AVFoundation and libmpv.
4. Add a simple playlist model that queues dropped files.
5. Replace the libmpv OpenGL renderer with a Metal-backed surface.
6. Add unit tests for `PlaybackFormatters.timeString(_:)`.
7. Add unit tests for `MPVPlaybackEngine` event handling and `PlayerStore`
   backend transitions.
8. Switch from `NSOpenPanel` to `fileImporter` and handle security-scoped
   resource access for sandboxing.
9. Add telemetry using `os.Logger` for open, prepare, play, pause, seek, EOF,
   and failure events.
