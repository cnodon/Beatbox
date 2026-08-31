import CoreAudio
import Foundation

enum CaptureInput: Equatable, Sendable {
    case microphone(deviceID: AudioDeviceID?)
    case application(
        processObjectIDs: [AudioObjectID],
        bundleIdentifiers: [String]
    )
}
