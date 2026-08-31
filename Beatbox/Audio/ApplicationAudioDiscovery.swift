import AppKit
import CoreAudio
import Foundation

struct ApplicationAudioDevice: Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let bundleIdentifier: String?
    let bundleURL: URL?
    let processObjectIDs: [AudioObjectID]
}

enum ApplicationAudioDiscoveryError: LocalizedError {
    case coreAudio(OSStatus)

    var errorDescription: String? {
        switch self {
        case let .coreAudio(status):
            "无法读取正在输出音频的 App（Core Audio 错误 \(status)）。"
        }
    }
}

struct ApplicationAudioDiscovery {
    func applications() throws -> [ApplicationAudioDevice] {
        let processObjectIDs = try processObjectList()
        let currentPID = ProcessInfo.processInfo.processIdentifier
        var groups: [String: ApplicationGroup] = [:]

        for processObjectID in processObjectIDs {
            guard (try? uint32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyIsRunningOutput
            )) != 0,
            let pidValue = try? int32Property(
                objectID: processObjectID,
                selector: kAudioProcessPropertyPID
            ),
            pidValue != currentPID
            else { continue }

            let runningApplication = NSRunningApplication(processIdentifier: pidValue)
            guard let runningApplication,
                  !runningApplication.isTerminated,
                  runningApplication.activationPolicy != .prohibited
            else { continue }
            let coreAudioBundleIdentifier = try? stringProperty(
                objectID: processObjectID,
                selector: kAudioProcessPropertyBundleID
            )
            let bundleIdentifier = nonempty(runningApplication.bundleIdentifier)
                ?? nonempty(coreAudioBundleIdentifier)
            let name = nonempty(runningApplication.localizedName)
                ?? bundleIdentifier
                ?? "进程 \(pidValue)"
            let stableID = bundleIdentifier.map { "application:\($0)" }
                ?? "application:pid:\(pidValue)"

            var group = groups[stableID] ?? ApplicationGroup(
                id: stableID,
                name: name,
                bundleIdentifier: bundleIdentifier,
                bundleURL: runningApplication.bundleURL,
                processObjectIDs: []
            )
            group.processObjectIDs.append(processObjectID)
            groups[stableID] = group
        }

        return groups.values
            .map { group in
                ApplicationAudioDevice(
                    id: group.id,
                    name: group.name,
                    bundleIdentifier: group.bundleIdentifier,
                    bundleURL: group.bundleURL,
                    processObjectIDs: group.processObjectIDs.sorted()
                )
            }
            .sorted { left, right in
                left.name.localizedStandardCompare(right.name) == .orderedAscending
            }
    }

    private struct ApplicationGroup {
        let id: String
        let name: String
        let bundleIdentifier: String?
        let bundleURL: URL?
        var processObjectIDs: [AudioObjectID]
    }

    private func processObjectList() throws -> [AudioObjectID] {
        let systemObject = AudioObjectID(kAudioObjectSystemObject)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var dataSize: UInt32 = 0
        try check(AudioObjectGetPropertyDataSize(systemObject, &address, 0, nil, &dataSize))

        let count = Int(dataSize) / MemoryLayout<AudioObjectID>.size
        guard count > 0 else { return [] }
        var values = [AudioObjectID](repeating: 0, count: count)
        let status = values.withUnsafeMutableBytes { bytes in
            guard let baseAddress = bytes.baseAddress else {
                return kAudioHardwareUnspecifiedError
            }
            return AudioObjectGetPropertyData(
                systemObject,
                &address,
                0,
                nil,
                &dataSize,
                baseAddress
            )
        }
        try check(status)
        return values
    }

    private func uint32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> UInt32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: UInt32 = 0
        var dataSize = UInt32(MemoryLayout<UInt32>.size)
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value))
        return value
    }

    private func int32Property(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> Int32 {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Int32 = 0
        var dataSize = UInt32(MemoryLayout<Int32>.size)
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value))
        return value
    }

    private func stringProperty(
        objectID: AudioObjectID,
        selector: AudioObjectPropertySelector
    ) throws -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var value: Unmanaged<CFString>?
        var dataSize = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        try check(AudioObjectGetPropertyData(objectID, &address, 0, nil, &dataSize, &value))
        guard let value else {
            throw ApplicationAudioDiscoveryError.coreAudio(kAudioHardwareUnspecifiedError)
        }
        return value.takeUnretainedValue() as String
    }

    private func nonempty(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }

    private func check(_ status: OSStatus) throws {
        guard status == noErr else {
            throw ApplicationAudioDiscoveryError.coreAudio(status)
        }
    }
}
