import Foundation

nonisolated enum VideoExportError: LocalizedError, Sendable {
    case sourceMissing
    case sourceAndDestinationMatch
    case copyFailed(String)

    var errorDescription: String? {
        switch self {
        case .sourceMissing:
            "找不到原始录屏文件。"
        case .sourceAndDestinationMatch:
            "导出位置不能覆盖 Beatbox 资料库中的原始文件。"
        case let .copyFailed(message):
            "录屏导出失败：\(message)"
        }
    }
}

nonisolated struct VideoExporter: Sendable {
    @concurrent
    func export(sourceURL: URL, destinationURL: URL) async throws -> URL {
        try Task.checkCancellation()
        let fileManager = FileManager.default
        guard fileManager.fileExists(atPath: sourceURL.path) else {
            throw VideoExportError.sourceMissing
        }
        guard sourceURL.standardizedFileURL != destinationURL.standardizedFileURL else {
            throw VideoExportError.sourceAndDestinationMatch
        }

        let temporaryURL = fileManager.temporaryDirectory
            .appending(path: "Beatbox-Video-Export-\(UUID().uuidString).mov")
        do {
            try fileManager.copyItem(at: sourceURL, to: temporaryURL)
            try Task.checkCancellation()
            if fileManager.fileExists(atPath: destinationURL.path) {
                _ = try fileManager.replaceItemAt(destinationURL, withItemAt: temporaryURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
            return destinationURL
        } catch is CancellationError {
            try? fileManager.removeItem(at: temporaryURL)
            throw CancellationError()
        } catch let error as VideoExportError {
            try? fileManager.removeItem(at: temporaryURL)
            throw error
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            throw VideoExportError.copyFailed(error.localizedDescription)
        }
    }
}
