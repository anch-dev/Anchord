import SwiftUI
import SwiftData

@main
struct AnchordApp: App {
    var body: some Scene {
        WindowGroup {
            RootView()
        }
        .modelContainer(for: [SongProject.self])
    }
}
