import SwiftUI

struct PlaybackControlsView: View {
    @Bindable var store: PlayerStore

    private let speedOptions = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]

    var body: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 12) {
                timeline

                HStack(spacing: 12) {
                    Button {
                        store.skip(by: -10)
                    } label: {
                        Label("Back 10 Seconds", systemImage: "gobackward.10")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.leftArrow, modifiers: .command)

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
                    .keyboardShortcut(.space, modifiers: [])
                    .buttonStyle(.glassProminent)

                    Button {
                        store.skip(by: 10)
                    } label: {
                        Label("Forward 10 Seconds", systemImage: "goforward.10")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut(.rightArrow, modifiers: .command)

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
                    .keyboardShortcut("m", modifiers: [])

                    Slider(value: $store.volume, in: 0...1)
                        .frame(width: 112)
                        .accessibilityLabel("Volume")

                    Picker("Speed", selection: $store.playbackRate) {
                        ForEach(speedOptions, id: \.self) { speed in
                            Text(speedLabel(speed))
                                .tag(speed)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 92)

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
                        }
                        .frame(width: 148)
                    }

                    Button {
                        store.toggleFullScreen()
                    } label: {
                        Label("Full Screen", systemImage: "arrow.up.left.and.arrow.down.right")
                            .labelStyle(.iconOnly)
                    }
                    .keyboardShortcut("f", modifiers: [.command, .control])
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
            .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
        }
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
