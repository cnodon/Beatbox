import Foundation

extension TimeInterval {
    var beatboxTimestamp: String {
        guard isFinite, self >= 0 else { return "00:00" }
        let totalSeconds = Int(self.rounded(.down))
        let hours = totalSeconds / 3_600
        let minutes = (totalSeconds % 3_600) / 60
        let seconds = totalSeconds % 60
        if hours > 0 {
            return String(format: "%02d:%02d:%02d", hours, minutes, seconds)
        }
        return String(format: "%02d:%02d", minutes, seconds)
    }
}

extension Int64 {
    var beatboxFileSize: String {
        ByteCountFormatter.string(fromByteCount: self, countStyle: .file)
    }
}
