import AppKit
import UniformTypeIdentifiers

enum VideoExportPanel {
    static func destination(recordingTitle: String) -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.allowsOtherFileTypes = false
        panel.isExtensionHidden = false
        panel.allowedContentTypes = [.quickTimeMovie]
        panel.message = "选择 MOV 录屏的保存位置"
        panel.prompt = "导出"
        panel.nameFieldStringValue = "\(safeFileName(recordingTitle)).mov"
        guard panel.runModal() == .OK, let selectedURL = panel.url else { return nil }
        return selectedURL.deletingPathExtension().appendingPathExtension("mov")
    }

    private static func safeFileName(_ title: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: "/:")
        let sanitized = title
            .components(separatedBy: invalidCharacters)
            .joined(separator: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return sanitized.isEmpty ? "Beatbox Screen Recording" : sanitized
    }
}
