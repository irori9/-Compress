import Foundation

@MainActor
public final class ExtractionExecutor: ObservableObject {
    public static let shared = ExtractionExecutor()

    private var running: [UUID: Task<Void, Never>] = [:]
    private var tokens: [UUID: CancellationToken] = [:]
    @Published public private(set) var lastError: [UUID: String] = [:]

    private init() {}

    public func ensureStarted(queue: TaskQueue, task: ArchiveTask) {
        guard running[task.id] == nil else { return }
        guard task.state == .pending || task.state == .failed || task.state == .paused else { return }
        let token = CancellationToken()
        tokens[task.id] = token
        task.canCancel = true
        task.state = .running
        lastError[task.id] = nil

        running[task.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.running[task.id] = nil }
            let format = await ArchiveServiceRegistry.shared.probe(inputURL: task.sourceURL)
            guard let service = await ArchiveServiceRegistry.shared.service(for: format) else {
                task.state = .failed
                task.errorMessage = ArchiveError.unsupported("无法找到服务").localizedDescription
                return
            }
            do {
                try await service.extract(
                    inputURL: task.sourceURL,
                    destination: task.destinationURL,
                    password: nil,
                    progress: { [weak queue, weak task] p in
                        guard let task = task else { return }
                        queue?.updateProgress(for: task.id, progress: p)
                    },
                    cancellationToken: token
                )
                task.state = .completed
                task.canCancel = false
            } catch let err as ArchiveError {
                task.state = .failed
                task.errorMessage = err.errorDescription
                self.lastError[task.id] = err.errorDescription
            } catch is CancellationError {
                task.state = .cancelled
                task.canCancel = false
            } catch {
                task.state = .failed
                task.errorMessage = error.localizedDescription
                self.lastError[task.id] = error.localizedDescription
            }
        }
    }

    public func retry(queue: TaskQueue, task: ArchiveTask, password: String?) {
        // Cancel existing if any
        if let t = running[task.id] { t.cancel() }
        // Start with provided password
        let token = CancellationToken()
        tokens[task.id] = token
        task.canCancel = true
        task.state = .running
        lastError[task.id] = nil
        running[task.id] = Task { [weak self] in
            guard let self else { return }
            defer { self.running[task.id] = nil }
            let format = await ArchiveServiceRegistry.shared.probe(inputURL: task.sourceURL)
            guard let service = await ArchiveServiceRegistry.shared.service(for: format) else {
                task.state = .failed
                task.errorMessage = ArchiveError.unsupported("无法找到服务").localizedDescription
                return
            }
            do {
                try await service.extract(
                    inputURL: task.sourceURL,
                    destination: task.destinationURL,
                    password: password,
                    progress: { [weak queue, weak task] p in
                        guard let task = task else { return }
                        queue?.updateProgress(for: task.id, progress: p)
                    },
                    cancellationToken: token
                )
                task.state = .completed
                task.canCancel = false
            } catch let err as ArchiveError {
                task.state = .failed
                task.errorMessage = err.errorDescription
                self.lastError[task.id] = err.errorDescription
            } catch is CancellationError {
                task.state = .cancelled
                task.canCancel = false
            } catch {
                task.state = .failed
                task.errorMessage = error.localizedDescription
                self.lastError[task.id] = error.localizedDescription
            }
        }
    }

    public func cancel(task: ArchiveTask) {
        tokens[task.id]?.cancel()
    }
}
