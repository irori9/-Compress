import Foundation

public struct SevenZArchiveService: ArchiveService {
    public init() {}

    public var supportedFormats: [ArchiveFormat] { [.sevenZ] }

    public func probe(inputURL: URL) async -> ArchiveFormat? {
        // TODO: Use LzmaSDK-ObjC to probe in future.
        if inputURL.pathExtension.lowercased() == "7z" { return .sevenZ }
        return nil
    }

    public func extract(inputURL: URL, destination: URL, password: String?, progress: @escaping (ArchiveProgress) -> Void, cancellationToken: CancellationToken?) async throws {
        // TODO: Implement using LzmaSDK-ObjC
        throw NSError(domain: "SevenZArchiveService", code: -1, userInfo: [NSLocalizedDescriptionKey: "7z extraction not implemented"]) 
    }
}
