import Foundation

public final class CancellationToken: @unchecked Sendable {
    private let lock = NSLock()
    private var _isCancelled = false

    public var isCancelled: Bool { lock.withLock { _isCancelled } }

    public init() {}

    public func cancel() { lock.withLock { _isCancelled = true } }
}

private extension NSLock {
    func withLock<T>(_ body: () -> T) -> T {
        lock()
        defer { unlock() }
        return body()
    }
}
