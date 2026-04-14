import Foundation

struct MediaFile: Identifiable, Equatable {
    let id = UUID()
    let sourceURL: URL
    let playbackURL: URL
    let title: String
    let compatibilityNote: String

    var isPreparedCopy: Bool {
        sourceURL != playbackURL
    }

    var sourceDirectory: String {
        sourceURL.deletingLastPathComponent().path(percentEncoded: false)
    }
}

struct PreparedMedia: Equatable {
    let sourceURL: URL
    let playbackURL: URL
    let compatibilityNote: String
    let durationOverride: Double?
}

struct SubtitleTrack: Identifiable, Hashable {
    static let offID = "off"

    let id: String
    let title: String

    static let off = SubtitleTrack(id: offID, title: "Off")
}
