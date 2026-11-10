import SwiftData
import SwiftUI

@main
struct WakeoutApp: App {
    private let modelContainer: ModelContainer = {
        do {
            return try ModelContainer(for: AlarmEntry.self, WakeLogEntry.self)
        } catch {
            fatalError("SwiftData の ModelContainer を作成できませんでした: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(modelContainer)
    }
}
