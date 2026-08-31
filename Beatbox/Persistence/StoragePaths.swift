import Foundation

nonisolated struct StoragePaths: Sendable {
    let rootURL: URL

    var recordingsURL: URL {
        rootURL.appending(path: "Recordings", directoryHint: .isDirectory)
    }

    var karaokeURL: URL {
        rootURL.appending(path: "Karaoke", directoryHint: .isDirectory)
    }

    var karaokeStagingURL: URL {
        karaokeURL.appending(path: ".Staging", directoryHint: .isDirectory)
    }

    init(rootURL: URL) {
        self.rootURL = rootURL
    }

    static func live(fileManager: FileManager = .default) throws -> StoragePaths {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        return StoragePaths(
            rootURL: applicationSupport.appending(path: "Beatbox", directoryHint: .isDirectory)
        )
    }

    func prepare(fileManager: FileManager = .default) throws {
        try fileManager.createDirectory(at: recordingsURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: karaokeURL, withIntermediateDirectories: true)
        try fileManager.createDirectory(at: karaokeStagingURL, withIntermediateDirectories: true)
    }

    func inProgressURL(for id: UUID, mode: RecordingMode = .audio) -> URL {
        recordingsURL.appending(path: "\(id.uuidString).inprogress.\(mode.fileExtension)")
    }

    func finalURL(for id: UUID, mode: RecordingMode = .audio) -> URL {
        recordingsURL.appending(path: "\(id.uuidString).\(mode.fileExtension)")
    }

    func url(for fileName: String) -> URL {
        recordingsURL.appending(path: fileName)
    }

    func karaokeAudioURL(for id: UUID, fileExtension: String) -> URL {
        karaokeURL.appending(path: "\(id.uuidString).\(fileExtension)")
    }

    func karaokeLyricsURL(for id: UUID) -> URL {
        karaokeURL.appending(path: "\(id.uuidString).lrc")
    }

    func karaokeURL(for fileName: String) -> URL {
        karaokeURL.appending(path: fileName)
    }

    func karaokeStagingURL(for id: UUID) -> URL {
        karaokeStagingURL.appending(path: id.uuidString, directoryHint: .isDirectory)
    }

    func inProgressFiles(fileManager: FileManager = .default) throws -> [URL] {
        let files = try fileManager.contentsOfDirectory(
            at: recordingsURL,
            includingPropertiesForKeys: [.fileSizeKey, .creationDateKey],
            options: [.skipsHiddenFiles]
        )
        return files.filter {
            $0.lastPathComponent.hasSuffix(".inprogress.m4a")
                || $0.lastPathComponent.hasSuffix(".inprogress.mov")
        }
    }
}
