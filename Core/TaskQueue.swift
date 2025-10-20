import Foundation
import Combine

@MainActor
public final class TaskQueue: ObservableObject {
    @Published public private(set) var tasks: [ArchiveTask] = []
    @Published public var maxConcurrentTasks: Int = 2

    public init() {}

    @discardableResult
    public func addTask(from url: URL) -> ArchiveTask {
        let destination = defaultDestination(for: url)
        let task = ArchiveTask(sourceURL: url, destinationURL: destination, format: .auto)
        tasks.insert(task, at: 0)
        schedule()
        return task
    }

    @discardableResult
    public func addTask(from url: URL, to destination: URL, format: ArchiveFormat = .auto) -> ArchiveTask {
        let task = ArchiveTask(sourceURL: url, destinationURL: destination, format: format)
        tasks.insert(task, at: 0)
        schedule()
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
        ExtractionExecutor.shared.cancel(task: task)
        schedule()
        objectWillChange.send()
    }

    public func pause(taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[idx]
        ExtractionExecutor.shared.pause(task: task)
    }

    public func resume(taskID: UUID) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        let task = tasks[idx]
        if task.state == .paused || task.state == .failed || task.state == .pending {
            task.state = .pending
            schedule()
        }
    }

    public func remove(taskID: UUID) {
        tasks.removeAll { $0.id == taskID }
    }

    public func setPriority(taskID: UUID, priority: ArchiveTaskPriority) {
        guard let idx = tasks.firstIndex(where: { $0.id == taskID }) else { return }
        tasks[idx].priority = priority
        // Reorder tasks list to reflect priority
        tasks.sort(by: { lhs, rhs in
            if lhs.state == .running && rhs.state != .running { return true }
            if lhs.state != .running && rhs.state == .running { return false }
            if lhs.priority != rhs.priority { return lhs.priority.rawValue > rhs.priority.rawValue }
            return lhs.createdAt > rhs.createdAt
        })
        schedule()
    }

    public func schedule() {
        // Start pending tasks up to the concurrency limit, by priority then creation date
        let runningCount = tasks.filter { $0.state == .running }.count
        if runningCount >= maxConcurrentTasks { return }
        let capacity = maxConcurrentTasks - runningCount
        let candidates = tasks.filter { $0.state == .pending }
            .sorted {
                if $0.priority != $1.priority { return $0.priority.rawValue > $1.priority.rawValue }
                return $0.createdAt < $1.createdAt
            }
            .prefix(capacity)
        for t in candidates {
            ExtractionExecutor.shared.ensureStarted(queue: self, task: t)
        }
    }

    private func defaultDestination(for url: URL) -> URL {
        let folderName = url.deletingPathExtension().lastPathComponent
        // Prefer extracting beside the source file when we have security-scoped access
        if SecurityScopedBookmarkStore.shared.startAccessIfBookmarked(for: url) {
            let dir = url.deletingLastPathComponent()
            return dir.appendingPathComponent(folderName, isDirectory: true)
        }
        // Fallback to app Documents directory
        let base = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        return base.appendingPathComponent(folderName, isDirectory: true)
    }
}
