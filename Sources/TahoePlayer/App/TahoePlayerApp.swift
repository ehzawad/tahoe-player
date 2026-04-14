import SwiftUI

@main
struct TahoePlayerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var playerStore = PlayerStore()

    var body: some Scene {
        WindowGroup("Tahoe Player") {
            ContentView()
                .environment(playerStore)
                .onAppear {
                    AppDelegate.attach(playerStore: playerStore)
                }
        }
        .commands {
            PlayerCommands(store: playerStore)
        }
        .defaultSize(width: 1100, height: 640)
        .defaultWindowPlacement { _, context in
            let display = context.defaultDisplay.visibleRect
            let width = min(display.width * 0.72, 1100)
            let height = min(width * 9 / 16, display.height * 0.72)
            return WindowPlacement(size: CGSize(width: width, height: height))
        }
        .windowIdealPlacement { _, context in
            let display = context.defaultDisplay.visibleRect
            let width = display.width * 0.86
            let height = min(width * 9 / 16, display.height * 0.86)
            return WindowPlacement(size: CGSize(width: width, height: height))
        }
    }
}

struct PlayerCommands: Commands {
    let store: PlayerStore

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Media...") {
                store.presentOpenPanel()
            }
            .keyboardShortcut("o", modifiers: [.command])
        }

        CommandMenu("Playback") {
            Button(store.isPlaying ? "Pause" : "Play") {
                store.togglePlayback()
            }
            .keyboardShortcut(.space, modifiers: [])
            .disabled(!store.hasMedia)

            Button("Skip Back 10 Seconds") {
                store.skip(by: -10)
            }
            .keyboardShortcut(.leftArrow, modifiers: [.command])
            .disabled(!store.hasMedia)

            Button("Skip Forward 10 Seconds") {
                store.skip(by: 10)
            }
            .keyboardShortcut(.rightArrow, modifiers: [.command])
            .disabled(!store.hasMedia)

            Button(store.isMuted ? "Unmute" : "Mute") {
                store.toggleMute()
            }
            .keyboardShortcut("m", modifiers: [])
            .disabled(!store.hasMedia)

            Divider()

            Button("Reveal Source in Finder") {
                store.revealSourceInFinder()
            }
            .disabled(store.media == nil)
        }
    }
}
