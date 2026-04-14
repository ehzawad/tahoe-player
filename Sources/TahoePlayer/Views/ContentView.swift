import AppKit
import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @Environment(PlayerStore.self) private var store
    @State private var didConstrainWindow = false

    var body: some View {
        @Bindable var store = store

        ZStack {
            Color.black.ignoresSafeArea()

            PlayerSurfaceView(store: store) {
                store.toggleFullScreen()
            }
                .ignoresSafeArea()

            if !store.hasMedia && !store.isPreparing {
                EmptyPlayerView(store: store)
                    .transition(.opacity)
            }

            if store.isPreparing {
                PreparingView(message: store.preparationMessage)
                    .transition(.scale.combined(with: .opacity))
            }

            if store.hasMedia {
                FloatingPlaybackControlsOverlay(store: store)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if let errorMessage = store.errorMessage {
                ErrorBanner(message: errorMessage) {
                    store.dismissError()
                }
                .padding(.top, 16)
                .padding(.horizontal, 20)
                .frame(maxHeight: .infinity, alignment: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .animation(.snappy(duration: 0.22), value: store.hasMedia)
        .animation(.snappy(duration: 0.22), value: store.isPreparing)
        .animation(.snappy(duration: 0.22), value: store.errorMessage)
        .frame(minWidth: 760, minHeight: 430)
        .onAppear {
            guard !didConstrainWindow else { return }
            didConstrainWindow = true
            constrainInitialWindowFrame()
        }
        .onDrop(
            of: [UTType.fileURL.identifier],
            isTargeted: $store.isDropTargeted,
            perform: store.handleDrop
        )
        .overlay(alignment: .top) {
            // Restore window dragging since the toolbar background is hidden.
            Color.clear
                .frame(height: 46)
                .contentShape(Rectangle())
                .simultaneousGesture(
                    TapGesture(count: 2)
                        .onEnded {
                            store.toggleFullScreen()
                        }
                )
                .gesture(WindowDragGesture())
                .allowsWindowActivationEvents(true)
        }
        .toolbar(removing: .title)
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let media = store.media {
                    VStack(spacing: 1) {
                        Text(media.title)
                            .font(.headline)
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if !media.compatibilityNote.isEmpty {
                            Text(media.compatibilityNote)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .frame(maxWidth: 520)
                }
            }

            ToolbarItem {
                Button {
                    store.presentOpenPanel()
                } label: {
                    Label("Open Media", systemImage: "folder")
                }
            }

            ToolbarItem {
                Button {
                    store.revealSourceInFinder()
                } label: {
                    Label("Reveal in Finder", systemImage: "arrow.up.forward.square")
                }
                .disabled(!store.hasMedia)
            }
        }
    }

    private func constrainInitialWindowFrame() {
        DispatchQueue.main.async {
            guard let window = NSApp.keyWindow ?? NSApp.windows.first(where: \.isVisible) else { return }
            window.minSize = NSSize(width: 760, height: 430)

            let visibleFrame = (window.screen ?? NSScreen.main)?.visibleFrame
                ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
            let width = min(1100, visibleFrame.width * 0.72)
            let height = min(width * 9 / 16, visibleFrame.height * 0.72)
            let current = window.frame
            let isAwkwardLaunchFrame = current.width > visibleFrame.width * 0.9
                || current.height > visibleFrame.height * 0.9
                || current.width / max(current.height, 1) > 3
                || current.height / max(current.width, 1) > 2

            guard isAwkwardLaunchFrame else { return }

            let nextFrame = NSRect(
                x: visibleFrame.midX - width / 2,
                y: visibleFrame.midY - height / 2,
                width: width,
                height: height
            )
            window.setFrame(nextFrame, display: true, animate: false)
        }
    }
}

// MARK: – Empty State

private struct EmptyPlayerView: View {
    let store: PlayerStore

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "play.rectangle.on.rectangle")
                .font(.system(size: 68, weight: .regular))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)

            VStack(spacing: 8) {
                Text("Open a local video")
                    .font(.system(.largeTitle, design: .rounded, weight: .semibold))

                Text("MP4 and MOV use AVFoundation. MKV, WebM, AVI, and transport streams play directly with libmpv.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 520)
            }

            HStack(spacing: 10) {
                Button {
                    store.presentOpenPanel()
                } label: {
                    Label("Open Media", systemImage: "folder")
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)

                Text("or drop a file here")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(32)
        .glassEffect(.regular, in: .rect(cornerRadius: 18))
        .opacity(store.isDropTargeted ? 0.72 : 1)
    }
}

// MARK: – Preparing State

private struct PreparingView: View {
    let message: String

    var body: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)

            VStack(spacing: 6) {
                Text("Preparing media")
                    .font(.headline)

                Text(message.isEmpty ? "Converting this file for playback." : message)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .lineLimit(3)
                    .frame(maxWidth: 460)
            }
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 22)
        .frame(maxWidth: 540)
        .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
    }
}

// MARK: – Error Banner

private struct ErrorBanner: View {
    let message: String
    let dismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.yellow)

            Text(message)
                .font(.callout)
                .lineLimit(4)

            Spacer(minLength: 12)

            Button("Dismiss", action: dismiss)
                .buttonStyle(.glass)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(.regular.tint(.red.opacity(0.22)).interactive(), in: .rect(cornerRadius: 14))
    }
}
