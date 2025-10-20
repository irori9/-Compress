import Foundation

public struct ArchiveProgress: Sendable {
    public var fractionCompleted: Double
    public var bytesPerSecond: Double?
    public var estimatedRemainingTime: TimeInterval?

    public init(fractionCompleted: Double, bytesPerSecond: Double? = nil, estimatedRemainingTime: TimeInterval? = nil) {
        self.fractionCompleted = fractionCompleted
        self.bytesPerSecond = bytesPerSecond
        self.estimatedRemainingTime = estimatedRemainingTime
    }
}
