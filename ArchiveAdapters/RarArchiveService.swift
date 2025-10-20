import Foundation

public struct RarArchiveService: ArchiveService {
    public init() {}

    public var supportedFormats: [ArchiveFormat] { [.rar] }

    public func probe(inputURL: URL) async -> ArchiveFormat? {
        // TODO: Use UnrarKit to probe in future.
        if inputURL.pathExtension.lowercased() == "rar" { return .rar }
        return nil
    }

    public func extract(inputURL: URL, destination: URL, password: String?, progress: @escaping (ArchiveProgress) -> Void, cancellationToken: CancellationToken?) async throws {
        // TODO: Implement using UnrarKit
        throw NSError(domain: "RarArchiveService", code: -1, userInfo: [NSLocalizedDescriptionKey: "RAR extraction not implemented"]) 
    }
}
