import Combine
import Sparkle
import SwiftUI

@MainActor
final class SoftwareUpdateController: ObservableObject {
    @Published private(set) var canCheckForUpdates = false

    private let updaterController: SPUStandardUpdaterController

    init(startingUpdater: Bool = true) {
        updaterController = SPUStandardUpdaterController(
            startingUpdater: startingUpdater,
            updaterDelegate: nil,
            userDriverDelegate: nil
        )

        updaterController.updater
            .publisher(for: \.canCheckForUpdates)
            .assign(to: &$canCheckForUpdates)
    }

    func checkForUpdates() {
        updaterController.checkForUpdates(nil)
    }
}

struct CheckForUpdatesButton: View {
    @ObservedObject private var softwareUpdates: SoftwareUpdateController

    init(softwareUpdates: SoftwareUpdateController) {
        self.softwareUpdates = softwareUpdates
    }

    var body: some View {
        Button("检查更新…") {
            softwareUpdates.checkForUpdates()
        }
        .disabled(!softwareUpdates.canCheckForUpdates)
    }
}
