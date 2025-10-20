import SwiftUI

@main
struct ArchiveManagerApp: App {
    @StateObject private var taskQueue = TaskQueue()

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(taskQueue)
        }
    }
}
