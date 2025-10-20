import Foundation
import Combine

@MainActor
public final class TaskQueue: ObservableObject {
    @Published public private(set) var tasks: [ArchiveTask] = []

    public init() {}

    @discardableResult
    public func addTask(from url: URL) -> ArchiveTask {
        let destination = defaultDestination(for: url)
        let task = ArchiveTask(sourceURL: url, destinationURL: destination, format: .auto)
        tasks.insert(task, at: 0)
        return task
    }

    @discardableResult
    public func addTask(from url: URL, to destination: URL, format: ArchiveFormat = .auto) -> ArchiveTask {
        let task = ArchiveTask(sourceURL: url, destinationURL: destination, format: format)
        tasks.insert(task, at: 0)
        return task
    }

    public func updateProgress(for taskID: UUID, progress: ArchiveProgress) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[idx]
        task.progress = progress.fractionCompleted
        task.bytesPerSecond = progress.bytesPerSecond
        task.estimatedRemainingTime = progress.estimatedRemainingTime
        if progress.fractionCompleted >= 1.0 {
            task.state = .completed
            task.canCancel = false
        } else if task.state == .pending {
            task.state = .running
        }
        objectWillChange.send()
    }

    public func cancel(taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[idx]
        task.state = .cancelled
        task.canCancel = false
        objectWillChange.send()
    }

    public func remove(taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
    }

    private func defaultDestination(for url: URL) -> URL {
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let folderName = url.deletingPathExtension().lastPathComponent
        return base.appendingPathComponent(folderName, isDirectory: true)
    }
}
