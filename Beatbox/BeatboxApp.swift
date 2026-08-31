import SwiftData
import SwiftUI

@main
struct BeatboxApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private let modelContainer: ModelContainer
    private let softwareUpdates: SoftwareUpdateController
    @State private var appModel: AppModel

    init() {
        softwareUpdates = SoftwareUpdateController()

        do {
            let container = try ModelContainer(for: Recording.self, KaraokeSong.self)
            let storage = try StoragePaths.live()
            modelContainer = container
            _appModel = State(
                initialValue: try AppModel(
                    modelContext: container.mainContext,
                    storage: storage
                )
            )
        } catch {
            fatalError("Beatbox could not initialize its local library: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appModel)
                .modelContainer(modelContainer)
                .task {
                    appDelegate.appModel = appModel
                }
        }
        .defaultSize(width: 1_040, height: 680)
        .commands {
            BeatboxCommands(
                appModel: appModel,
                softwareUpdates: softwareUpdates
            )
        }

        Settings {
            SettingsView(softwareUpdates: softwareUpdates)
                .environment(appModel)
                .modelContainer(modelContainer)
        }
    }
}
