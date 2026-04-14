import SwiftUI

struct FloatingPlaybackControlsOverlay: View {
    let store: PlayerStore

    @State private var controlsOrigin: CGPoint?
    @State private var dragStartOrigin: CGPoint?

    private let controlsHeight: CGFloat = 106
    private let bottomMargin: CGFloat = 18
    private let topMargin: CGFloat = 52
    private let horizontalMargin: CGFloat = 20

    var body: some View {
        GeometryReader { proxy in
            let containerSize = proxy.size
            let controlsSize = preferredControlsSize(in: containerSize)
            let origin = resolvedOrigin(in: containerSize, controlsSize: controlsSize)

            PlaybackControlsView(
                store: store,
                onResetDrag: {
                    controlsOrigin = defaultOrigin(in: containerSize, controlsSize: controlsSize)
                    dragStartOrigin = nil
                },
                onDragBegan: {
                    dragStartOrigin = origin
                },
                onDragDelta: { translation in
                    guard let dragStartOrigin else { return }
                    controlsOrigin = clampedOrigin(
                        CGPoint(
                            x: dragStartOrigin.x + translation.width,
                            y: dragStartOrigin.y + translation.height
                        ),
                        in: containerSize,
                        controlsSize: controlsSize
                    )
                },
                onDragEnded: {
                    if let controlsOrigin {
                        self.controlsOrigin = clampedOrigin(
                            controlsOrigin,
                            in: containerSize,
                            controlsSize: controlsSize
                        )
                    }
                    dragStartOrigin = nil
                }
            )
            .frame(width: controlsSize.width, height: controlsSize.height)
            .position(
                x: origin.x + controlsSize.width / 2,
                y: origin.y + controlsSize.height / 2
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .onAppear {
                guard controlsOrigin == nil else { return }
                controlsOrigin = defaultOrigin(in: containerSize, controlsSize: controlsSize)
            }
            .onChange(of: containerSize) { _, newSize in
                let nextControlsSize = preferredControlsSize(in: newSize)
                let nextOrigin = controlsOrigin
                    ?? defaultOrigin(in: newSize, controlsSize: nextControlsSize)
                controlsOrigin = clampedOrigin(
                    nextOrigin,
                    in: newSize,
                    controlsSize: nextControlsSize
                )

                if dragStartOrigin != nil {
                    dragStartOrigin = controlsOrigin
                }
            }
        }
    }

    private func resolvedOrigin(in containerSize: CGSize, controlsSize: CGSize) -> CGPoint {
        let baseOrigin = controlsOrigin ?? defaultOrigin(in: containerSize, controlsSize: controlsSize)
        return clampedOrigin(baseOrigin, in: containerSize, controlsSize: controlsSize)
    }

    private func preferredControlsSize(in containerSize: CGSize) -> CGSize {
        let width = min(720, max(260, containerSize.width - horizontalMargin * 2))
        return CGSize(width: width, height: controlsHeight)
    }

    private func defaultOrigin(in containerSize: CGSize, controlsSize: CGSize) -> CGPoint {
        CGPoint(
            x: (containerSize.width - controlsSize.width) / 2,
            y: containerSize.height - controlsSize.height - bottomMargin
        )
    }

    private func clampedOrigin(
        _ origin: CGPoint,
        in containerSize: CGSize,
        controlsSize: CGSize
    ) -> CGPoint {
        let minX = horizontalMargin
        let maxX = containerSize.width - controlsSize.width - horizontalMargin
        let minY = topMargin
        let maxY = containerSize.height - controlsSize.height - bottomMargin

        return CGPoint(
            x: clamp(origin.x, lower: minX, upper: maxX),
            y: clamp(origin.y, lower: minY, upper: maxY)
        )
    }

    private func clamp(_ value: CGFloat, lower: CGFloat, upper: CGFloat) -> CGFloat {
        guard lower <= upper else {
            return (lower + upper) / 2
        }

        return min(max(value, lower), upper)
    }
}
