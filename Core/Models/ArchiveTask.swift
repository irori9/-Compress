import Foundation
import Combine

public enum ArchiveTaskState: String, Codable, Sendable {
    case pending
    case running
    case paused
    case completed
    case failed
    case cancelled
}

public enum ArchiveTaskPriority: Int, Codable, Sendable, CaseIterable {
    case low = 0
    case normal = 1
    case high = 2
}

public final class ArchiveTask: ObservableObject, Identifiable {
    public let id: UUID
    public let createdAt: Date
    public var sourceURL: URL
    public var destinationURL: URL
    public var format: ArchiveFormat

    @Published public var state: ArchiveTaskState
    @Published public var progress: Double // 0...1
    @Published public var bytesPerSecond: Double?
    @Published public var estimatedRemainingTime: TimeInterval?
    @Published public var canCancel: Bool
    @Published public var errorMessage: String?

    // Extended metadata for UI/UX and scheduling
    @Published public var priority: ArchiveTaskPriority
    @Published public var failedAttempts: Int
    @Published public var errorDetails: [String]
    @Published public var currentFileName: String?
    @Published public var totalItems: Int?

    public init(id: UUID = UUID(),
                sourceURL: URL,
                destinationURL: URL,
                format: ArchiveFormat = .auto,
                state: ArchiveTaskState = .pending,
                progress: Double = 0,
                bytesPerSecond: Double? = nil,
                estimatedRemainingTime: TimeInterval? = nil,
                canCancel: Bool = true,
                errorMessage: String? = nil,
                priority: ArchiveTaskPriority = .normal,
                failedAttempts: Int = 0,
                errorDetails: [String] = [],
                currentFileName: String? = nil,
                totalItems: Int? = nil) {
        self.id = id
        self.createdAt = Date()
        self.sourceURL = sourceURL
        self.destinationURL = destinationURL
        self.format = format
        self.state = state
        self.progress = progress
        self.bytesPerSecond = bytesPerSecond
        self.estimatedRemainingTime = estimatedRemainingTime
        self.canCancel = canCancel
        self.errorMessage = errorMessage
        self.priority = priority
        self.failedAttempts = failedAttempts
        self.errorDetails = errorDetails
        self.currentFileName = currentFileName
        self.totalItems = totalItems
    }
}
