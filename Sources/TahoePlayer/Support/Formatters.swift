import Foundation

enum PlaybackFormatters {
    static func timeString(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0 else { return "0:00" }

        let totalSeconds = Int(seconds.rounded(.down))
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let remainingSeconds = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, remainingSeconds)
        }

        return String(format: "%d:%02d", minutes, remainingSeconds)
    }
}

extension String {
    func trimmedForDisplay(limit: Int) -> String {
        guard count > limit else { return self.trimmingCharacters(in: .whitespacesAndNewlines) }
        let endIndex = index(startIndex, offsetBy: limit)
        return String(self[..<endIndex]).trimmingCharacters(in: .whitespacesAndNewlines) + "..."
    }
}
