import Foundation

public protocol ArchiveService {
    var supportedFormats: [ArchiveFormat] { get }

    func probe(inputURL: URL) async -> ArchiveFormat?

    func extract(
        inputURL: URL,
        destination: URL,
        password: String?,
        progress: @escaping (ArchiveProgress) -> Void,
        cancellationToken: CancellationToken?
    ) async throws
}
