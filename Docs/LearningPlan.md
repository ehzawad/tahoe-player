# macOS Tahoe Media Player — Learning Plan

Scoped to this app: a local-file macOS video player with SwiftUI,
AVPlayerLayer video rendering, SwiftUI playback controls, Liquid Glass on
navigation/control surfaces, a PlaybackEngine protocol boundary, and a pragmatic
compatibility path for files AVFoundation cannot open directly.

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
- Liquid Glass overview: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views
- WindowDragGesture: https://developer.apple.com/documentation/swiftui/windowdraggesture

---

## Part A: Platform Core

### Concepts
- A real Mac app is built around **windows, menus, toolbars, keyboard
  commands, file access, and full-screen behavior** — not "a screen
  with a video widget."
- `WindowGroup` is the scene type for document-like windows.
- `Commands` adds native menu-bar items with keyboard shortcuts.
- `@NSApplicationDelegateAdaptor` bridges AppKit lifecycle events
  (Dock icon clicks, Finder open-file) into a SwiftUI app.

### Where this lives in the code
- `TahoePlayerApp.swift` — scene, commands, window placement.
- `AppDelegate.swift` — foreground activation, Finder open-file handling.

### Apple doc links
- SwiftUI App protocol, WindowGroup, Commands
- NSApplicationDelegate

### Checkpoint questions
1. Why is `WindowGroup` the right starting point for this app?
2. Why bother with menu commands before any media feature exists?
3. What does `AppDelegate.attach(playerStore:)` solve that pure
   SwiftUI lifecycle cannot?

---

## Part B: Media Core

### Concepts
The conceptual stack is:

    URL → AVAsset → AVPlayerItem → AVPlayer → AVPlayerLayer

- **AVFoundation** models the media; the player item models the timed
  presentation; the player controls transport and track selection.
- **AVPlayerLayer** renders video in a small `NSViewRepresentable`
  bridge while SwiftUI owns the transport controls.
- The SwiftUI controls provide play/pause, scrubber, volume, speed,
  subtitle selection, and full-screen actions on a Liquid Glass surface.
- The **PlaybackEngine protocol** decouples the UI from a specific
  decoder. The app ships with AVFoundation; a future engine (libmpv,
  VLCKit) can slot in without rewiring views.

### Where this lives in the code
- `PlaybackEngine.swift` — narrow playback backend protocol.
- `AVFoundationPlaybackEngine.swift` — concrete implementation.
- `PlayerSurfaceView.swift` — `NSViewRepresentable` wrapping AVPlayerLayer.
- `PlayerStore.swift` — observable state, owns the engine, syncs
  via KVO (timeControlStatus, periodic time observer).

### Apple doc links
- AVPlayerLayer, AVPlayer, AVPlayerItem, AVURLAsset
- AVMediaSelectionGroup, AVMediaSelectionOption
- NSViewRepresentable

### Checkpoint questions
1. Can you explain the difference between AVAsset, AVPlayerItem,
   AVPlayer, and AVPlayerLayer without hand-waving?
2. Why did this app choose SwiftUI-owned controls instead of native
   AVKit controls?
3. Why keep a PlaybackEngine abstraction even for an Apple-native MVP?
4. How does the KVO observer on `timeControlStatus` keep the menu's
   "Play/Pause" label correct?

---

## Part C: File Opening & Format Boundary

### Concepts
- `NSOpenPanel` is the AppKit file picker. `fileImporter` is the
  SwiftUI-native equivalent (preferred for sandboxed apps).
- **UTType** defines what files the picker shows. MKV is not a
  first-class AVFoundation type — the system may or may not
  recognise `org.matroska.mkv` depending on installed software.
- Apple explicitly foregrounds QuickTime/MPEG-4/HLS. MKV must be
  treated as **unguaranteed** unless a runtime probe proves otherwise.
- `AVURLAsset.load(.isPlayable)` is the runtime gate.
- `MediaPreparationService` falls back to FFmpeg remux when
  AVFoundation can't play a file directly.
- MKV text subtitles are converted to MP4 `mov_text` and then surfaced
  through AVFoundation legible media selection groups.

### Where this lives in the code
- `PlayerStore.presentOpenPanel()` — file picker.
- `PlayerStore.handleDrop(_:)` — drag & drop.
- `MediaPreparationService.swift` — playable check + FFmpeg path.
- `MediaFile.swift` — model tracking source vs. playback URL.

### Apple doc links
- NSOpenPanel, fileImporter, UTType
- AVURLAsset, AVAsset.load(.isPlayable)
- App Sandbox file access (for future sandboxing)

### Checkpoint questions
1. Why can a file conform to `public.movie` but still fail
   `AVURLAsset.load(.isPlayable)`?
2. What exactly is "supported" here: a file extension, a container,
   the codecs inside it, or the backend's runtime capability?
3. What should happen if FFmpeg is missing and the user opens an MKV?
4. How should the player behave when a new file is opened while
   another file is playing?

---

## Part D: Tahoe Design

### Concepts
- Liquid Glass is **not** a license to smear translucent effects
  everywhere. Standard SwiftUI/AppKit controls pick up the new
  material automatically.
- Glass belongs on the **navigation/control layer** (toolbar, sidebar,
  modal overlays), never on the **content layer** (the video itself).
- The app uses `.glassEffect()` only on the empty-state card,
  preparing overlay, error banner, and custom playback controls — all
  non-content surfaces.
- Test with Reduced Transparency and Increased Contrast enabled
  in macOS accessibility settings.

### Where this lives in the code
- `ContentView.swift` — EmptyPlayerView uses `.glassEffect(.regular)`.
- `ContentView.swift` — PreparingView, ErrorBanner use glass variants.
- Toolbar items get system glass automatically.

### Checkpoint questions
1. Where should glass exist in this app, and where should it not?
2. What happens to glass effects when the user enables Reduced
   Transparency?
3. Why is `.toolbarBackgroundVisibility(.hidden)` used — and how
   does it interact with Liquid Glass?

---

## Code Map

```
Sources/TahoePlayer/
├── App/
│   ├── TahoePlayerApp.swift           — scene, commands, window sizing
│   └── AppDelegate.swift              — Dock activation, Finder open-file
├── Stores/
│   └── PlayerStore.swift              — @Observable state, owns engine, KVO sync
├── Services/
│   ├── PlaybackEngine.swift           — narrow playback backend protocol
│   ├── AVFoundationPlaybackEngine.swift — AVPlayer + MediaPreparationService
│   └── MediaPreparationService.swift  — isPlayable check, FFmpeg remux
├── Models/
│   └── MediaFile.swift                — source/playback URL, title, compat note
├── Views/
│   ├── ContentView.swift              — player surface, toolbar, overlays, drop
│   ├── PlaybackControlsView.swift     — transport, volume, speed, subtitles
│   └── PlayerSurfaceView.swift        — NSViewRepresentable → AVPlayerLayer
└── Support/
    └── Formatters.swift               — time string formatting
```

---

## Coding Exercises

1. Add `J` / `L` shortcut pair for skip back/forward.
2. Add a recent-files menu using `@AppStorage` and security-scoped
   bookmarks (prep for future sandboxing).
3. Add an audio track selector after inspecting
   `AVAsset` media selection groups.
4. Add a simple playlist model that queues dropped files.
5. Replace the FFmpeg preparation path with a real mpv/libmpv
   renderer behind the PlaybackEngine protocol.
6. Add unit tests for `PlaybackFormatters.timeString(_:)`.
7. Add telemetry using `os.Logger` for open, prepare, play, pause,
   seek, and failure events.
8. Switch from `NSOpenPanel` to `fileImporter` and handle
   security-scoped resource access for sandboxing.
9. Add Picture-in-Picture support investigation for the custom
   `AVPlayerLayer` surface.
