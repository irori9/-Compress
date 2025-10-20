import SwiftUI
#if canImport(BackgroundTasks)
import BackgroundTasks
#endif

@main
struct ArchiveManagerApp: App {
    @StateObject private var taskQueue = TaskQueue()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            HomeView()
                .environmentObject(taskQueue)
                .onAppear {
                    registerBackgroundTasks()
                    resumePendingCheckpoints()
                }
                .onChange(of: scenePhase) { _, newPhase in
                    switch newPhase {
                    case .background:
                        scheduleBackgroundProcessing()
                    default:
                        break
                    }
                }
        }
    }

    private func resumePendingCheckpoints() {
        let cps = ExtractionCheckpointStore.listAll()
        for cp in cps {
            let src = URL(fileURLWithPath: cp.sourcePath)
            let dest = URL(fileURLWithPath: cp.destinationPath)
            let task = taskQueue.addTask(from: src, to: dest, format: .auto)
            ExtractionExecutor.shared.ensureStarted(queue: taskQueue, task: task)
        }
    }

    private func registerBackgroundTasks() {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            BGTaskScheduler.shared.register(forTaskWithIdentifier: "com.archivemanager.extract", using: nil) { task in
                handleBackgroundTask(task: task)
            }
        }
        #endif
    }

    private func scheduleBackgroundProcessing() {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            let request = BGProcessingTaskRequest(identifier: "com.archivemanager.extract")
            request.requiresNetworkConnectivity = false
            request.requiresExternalPower = false
            request.earliestBeginDate = Date(timeIntervalSinceNow: 5 * 60)
            try? BGTaskScheduler.shared.submit(request)
        }
        #endif
    }

    private func handleBackgroundTask(task: BGTask) {
        #if canImport(BackgroundTasks)
        if #available(iOS 13.0, *) {
            resumePendingCheckpoints()
            task.expirationHandler = {
                // Let running tasks capture their own checkpoints on cancellation
                // Nothing to do here in this scaffold
            }
            // Mark as completed after scheduling resumes; actual completion is managed by our services
            task.setTaskCompleted(success: true)
            scheduleBackgroundProcessing()
        }
        #endif
    }
}
