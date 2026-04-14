import AppKit
import AVFoundation
import OpenGL.GL3
import QuartzCore
import SwiftUI

struct PlayerSurfaceView: View {
    let store: PlayerStore
    let onDoubleClick: () -> Void

    var body: some View {
        if store.usesMPVPlayback {
            MPVPlayerSurfaceView(engine: store.mpvEngine, onDoubleClick: onDoubleClick)
        } else {
            AVPlayerSurfaceView(player: store.player, onDoubleClick: onDoubleClick)
        }
    }
}

/// Minimal AppKit bridge for rendering AVPlayer video and forwarding
/// double-click full-screen toggles to SwiftUI.
/// SwiftUI owns transport controls so they remain visible and predictable.
private struct AVPlayerSurfaceView: NSViewRepresentable {
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

private final class PlayerLayerView: NSView {
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

private struct MPVPlayerSurfaceView: NSViewRepresentable {
    let engine: MPVPlaybackEngine
    let onDoubleClick: () -> Void

    func makeNSView(context: Context) -> MPVOpenGLPlayerView {
        let view = MPVOpenGLPlayerView()
        view.engine = engine
        view.onDoubleClick = onDoubleClick
        view.attachEngineIfReady()
        return view
    }

    func updateNSView(_ nsView: MPVOpenGLPlayerView, context: Context) {
        nsView.engine = engine
        nsView.onDoubleClick = onDoubleClick
        nsView.attachEngineIfReady()
    }
}

private final class MPVOpenGLPlayerView: NSOpenGLView {
    weak var engine: MPVPlaybackEngine?
    var onDoubleClick: (() -> Void)?
    private var didPrepareOpenGL = false

    init() {
        super.init(frame: .zero, pixelFormat: Self.makePixelFormat())!
        wantsBestResolutionOpenGLSurface = true
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        nil
    }

    override var acceptsFirstResponder: Bool {
        true
    }

    override var isOpaque: Bool {
        true
    }

    override func prepareOpenGL() {
        super.prepareOpenGL()

        openGLContext?.makeCurrentContext()
        var swapInterval: GLint = 1
        openGLContext?.setValues(&swapInterval, for: .swapInterval)
        didPrepareOpenGL = true
        attachEngineIfReady()
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        attachEngineIfReady()
    }

    override func viewDidChangeBackingProperties() {
        super.viewDidChangeBackingProperties()
        needsDisplay = true
    }

    override func reshape() {
        super.reshape()
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        openGLContext?.makeCurrentContext()
        glClearColor(0, 0, 0, 1)
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))

        let backingSize = convertToBacking(bounds).size
        let width = Int32(max(0, backingSize.width.rounded(.down)))
        let height = Int32(max(0, backingSize.height.rounded(.down)))

        if let engine, width > 0, height > 0 {
            engine.render(width: width, height: height)
        } else {
            openGLContext?.flushBuffer()
        }
    }

    func attachEngineIfReady() {
        guard didPrepareOpenGL, window != nil, let openGLContext, let engine else { return }
        engine.attach(to: openGLContext, updateView: self)
        needsDisplay = true
    }

    override func mouseDown(with event: NSEvent) {
        if event.clickCount == 2 {
            onDoubleClick?()
            return
        }

        super.mouseDown(with: event)
    }

    private static func makePixelFormat() -> NSOpenGLPixelFormat {
        let attributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            UInt32(NSOpenGLPFAColorSize), UInt32(24),
            UInt32(NSOpenGLPFAAlphaSize), UInt32(8),
            UInt32(NSOpenGLPFADepthSize), UInt32(0),
            UInt32(NSOpenGLPFAOpenGLProfile), UInt32(NSOpenGLProfileVersion3_2Core),
            0
        ]

        if let pixelFormat = NSOpenGLPixelFormat(attributes: attributes) {
            return pixelFormat
        }

        let fallbackAttributes: [NSOpenGLPixelFormatAttribute] = [
            UInt32(NSOpenGLPFAAccelerated),
            UInt32(NSOpenGLPFADoubleBuffer),
            0
        ]
        guard let fallbackPixelFormat = NSOpenGLPixelFormat(attributes: fallbackAttributes) else {
            preconditionFailure("Tahoe Player could not create an OpenGL pixel format for libmpv.")
        }
        return fallbackPixelFormat
    }
}
