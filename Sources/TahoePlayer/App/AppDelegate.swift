import AppKit
import Foundation

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    weak static var playerStore: PlayerStore?
    private static var pendingOpenURLs: [URL] = []

    static func attach(playerStore store: PlayerStore) {
        playerStore = store

        guard !pendingOpenURLs.isEmpty else { return }

        let urls = pendingOpenURLs
        pendingOpenURLs.removeAll()

        Task { @MainActor in
            for url in urls {
                await store.load(url: url)
            }
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)

        if let launchFile = ProcessInfo.processInfo.environment["TAHOEPLAYER_OPEN_FILE"] {
            open(URL(fileURLWithPath: launchFile))
        }

        CommandLine.arguments
            .dropFirst()
            .map(URL.init(fileURLWithPath:))
            .filter { FileManager.default.fileExists(atPath: $0.path(percentEncoded: false)) }
            .forEach(open)
    }

    func applicationWillTerminate(_ notification: Notification) {
        Self.playerStore?.shutdown()
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        false
    }

    func application(_ sender: NSApplication, openFile filename: String) -> Bool {
        open(URL(fileURLWithPath: filename))
        return true
    }

    func application(_ sender: NSApplication, openFiles filenames: [String]) {
        filenames
            .map(URL.init(fileURLWithPath:))
            .forEach(open)
        sender.reply(toOpenOrPrint: .success)
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        urls.forEach(open)
    }

    private func open(_ url: URL) {
        guard let playerStore = Self.playerStore else {
            Self.pendingOpenURLs.append(url)
            return
        }

        Task { @MainActor in
            await playerStore.load(url: url)
        }
    }
}
