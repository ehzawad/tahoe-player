import SwiftUI

struct PlaybackControlsView: View {
    @Bindable var store: PlayerStore
    let onResetDrag: () -> Void
    let onDragBegan: () -> Void
    let onDragDelta: (CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var isDraggingHandle = false

    private let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    init(
        store: PlayerStore,
        onResetDrag: @escaping () -> Void = {},
        onDragBegan: @escaping () -> Void = {},
        onDragDelta: @escaping (CGSize) -> Void = { _ in },
        onDragEnded: @escaping () -> Void = {}
    ) {
        self.store = store
        self.onResetDrag = onResetDrag
        self.onDragBegan = onDragBegan
        self.onDragDelta = onDragDelta
        self.onDragEnded = onDragEnded
    }

    var body: some View {
        VStack(spacing: 10) {
            dragHandle
            timeline

            HStack(spacing: 8) {
                Button {
                    store.skip(by: -10)
                } label: {
                    Label("Back 10 Seconds", systemImage: "gobackward.10")
                        .labelStyle(.iconOnly)
                }

                Button {
                    store.togglePlayback()
                } label: {
                    Label(
                        store.isPlaying ? "Pause" : "Play",
                        systemImage: store.isPlaying ? "pause.fill" : "play.fill"
                    )
                    .labelStyle(.iconOnly)
                    .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderedProminent)

                Button {
                    store.skip(by: 10)
                } label: {
                    Label("Forward 10 Seconds", systemImage: "goforward.10")
                        .labelStyle(.iconOnly)
                }

                Divider()
                    .frame(height: 24)

                Button {
                    store.toggleMute()
                } label: {
                    Label(
                        store.isMuted ? "Unmute" : "Mute",
                        systemImage: volumeSystemImage
                    )
                    .labelStyle(.iconOnly)
                }

                Slider(value: $store.volume, in: 0...1)
                    .frame(width: 82)
                    .accessibilityLabel("Volume")

                Picker("Speed", selection: $store.playbackRate) {
                    ForEach(speedOptions, id: \.self) { speed in
                        Text(speedLabel(speed))
                            .tag(speed)
                    }
                }
                .labelsHidden()
                .frame(width: 78)

                if store.subtitleTracks.count > 1 {
                    Menu {
                        ForEach(store.subtitleTracks) { track in
                            Button {
                                store.selectSubtitle(id: track.id)
                            } label: {
                                if track.id == store.selectedSubtitleID {
                                    Label(track.title, systemImage: "checkmark")
                                } else {
                                    Text(track.title)
                                }
                            }
                        }
                    } label: {
                        Label(store.selectedSubtitleTitle, systemImage: "captions.bubble")
                            .lineLimit(1)
                            .truncationMode(.tail)
                    }
                    .frame(width: 126)
                }

                Button {
                    store.toggleFullScreen()
                } label: {
                    Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                        .labelStyle(.iconOnly)
                }
                .keyboardShortcut("f", modifiers: [.command, .control])
            }
            .buttonStyle(.borderless)
            .controlSize(.regular)
        }
        .padding(.horizontal, 18)
        .padding(.top, 8)
        .padding(.bottom, 14)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.black.opacity(0.82))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(Color.white.opacity(0.16), lineWidth: 1)
        }
    }

    private var dragHandle: some View {
        Capsule(style: .continuous)
            .fill(Color.secondary.opacity(0.65))
            .frame(width: 42, height: 5)
            .frame(maxWidth: .infinity, minHeight: 16)
            .contentShape(Rectangle())
            .onTapGesture(count: 2, perform: onResetDrag)
            .gesture(
                DragGesture(minimumDistance: 0, coordinateSpace: .global)
                    .onChanged { value in
                        if !isDraggingHandle {
                            isDraggingHandle = true
                            onDragBegan()
                        }
                        onDragDelta(value.translation)
                    }
                    .onEnded { _ in
                        isDraggingHandle = false
                        onDragEnded()
                    }
            )
            .accessibilityLabel("Move Playback Controls")
            .accessibilityHint("Drag to move the floating controls. Double-click to reset.")
    }

    private var timeline: some View {
        HStack(spacing: 10) {
            Text(PlaybackFormatters.timeString(store.currentTime))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .trailing)

            Slider(
                value: Binding(
                    get: { store.currentTime },
                    set: { store.seekPreview(to: $0) }
                ),
                in: 0...max(store.duration, 1),
                onEditingChanged: { isEditing in
                    if isEditing {
                        store.isScrubbing = true
                    } else {
                        store.finishSeek()
                    }
                }
            )
            .accessibilityLabel("Playback Position")

            Text(PlaybackFormatters.timeString(store.duration))
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .frame(width: 58, alignment: .leading)
        }
        .font(.caption)
    }

    private func speedLabel(_ speed: Double) -> String {
        speed == 1 ? "1x" : "\(speed.formatted(.number.precision(.fractionLength(0...2))))x"
    }

    private var volumeSystemImage: String {
        guard !store.isMuted, store.volume > 0 else {
            return "speaker.slash.fill"
        }

        return store.volume < 0.45 ? "speaker.wave.1.fill" : "speaker.wave.2.fill"
    }
}
