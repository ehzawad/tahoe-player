import AppKit
import AVFoundation
import QuartzCore
import SwiftUI

/// Minimal AppKit bridge for rendering AVPlayer video and forwarding
/// double-click full-screen toggles to SwiftUI.
/// SwiftUI owns transport controls so they remain visible and predictable.
struct PlayerSurfaceView: NSViewRepresentable {
    let player: AVPlayer
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> PlayerLayerView {
        let view = PlayerLayerView()
        view.playerLayer.player = player
        view.onDoubleClick = onDoubleClick
        return view
    }

    func updateNSView(_ nsView: PlayerLayerView, context: Context) {
        if nsView.playerLayer.player !== player {
            nsView.playerLayer.player = player
        }
        nsView.onDoubleClick = onDoubleClick
    }
}

final class PlayerLayerView: NSView {
    let playerLayer = AVPlayerLayer()
    var onDoubleClick: (() -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        wantsLayer = true
        layer = CALayer()
        layer?.backgroundColor = NSColor.black.cgColor

        playerLayer.backgroundColor = NSColor.black.cgColor
        playerLayer.videoGravity = .resizeAspect
        layer?.addSublayer(playerLayer)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override func layout() {
        super.layout()
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        playerLayer.frame = bounds
        CATransaction.commit()
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        super.mouseDown(with: event)
    }
}
