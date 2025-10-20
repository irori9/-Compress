import Foundation

public struct ZipArchiveService: ArchiveService {
    public init() {}

    public var supportedFormats: [ArchiveFormat] { [.zip] }

    public func probe(inputURL: URL) async -> ArchiveFormat? {
        // TODO: Use ZIPFoundation to probe file headers in future.
        if inputURL.pathExtension.lowercased() == "zip" { return .zip }
        return nil
    }

    public func extract(inputURL: URL, destination: URL, password: String?, progress: @escaping (ArchiveProgress) -> Void, cancellationToken: CancellationToken?) async throws {
        // TODO: Implement using ZIPFoundation. For now, simulate fake progress.
        let steps = 20
        for i in 1...steps {
            try Task.checkCancellation()
            if cancellationToken?.isCancelled == true { throw CancellationError() }
            try await Task.sleep(nanoseconds: 50_000_000)
            progress(ArchiveProgress(fractionCompleted: Double(i) / Double(steps)))
        }
    }
}
