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

// MARK: - Resumable Extraction Checkpoint

/// A lightweight checkpoint record to support resume/cancel across crashes and restarts.
/// The checkpoint persists to a JSON file in the app's Caches directory.
struct ExtractionCheckpoint: Codable, Equatable {
    var id: UUID
    var sourcePath: String
    var destinationPath: String
    var totalBytes: UInt64
    var processedBytes: UInt64
    var partialFilePath: String?
    var updatedAt: Date

    init(id: UUID = UUID(), source: URL, destination: URL, totalBytes: UInt64, processedBytes: UInt64, partialFilePath: String?) {
        self.id = id
        self.sourcePath = source.path
        self.destinationPath = destination.path
        self.totalBytes = totalBytes
        self.processedBytes = processedBytes
        self.partialFilePath = partialFilePath
        self.updatedAt = Date()
    }
}

enum ExtractionCheckpointStore {
    private static var baseDirectory: URL {
        let fm = FileManager.default
        let base = fm.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL(fileURLWithPath: NSTemporaryDirectory())
        let dir = base.appendingPathComponent("ExtractionCheckpoints", isDirectory: true)
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Persist a checkpoint to disk, replacing any previous record for the same source+destination.
    static func save(_ cp: ExtractionCheckpoint) {
        let url = urlForCheckpoint(sourcePath: cp.sourcePath, destinationPath: cp.destinationPath)
        do {
            let data = try JSONEncoder().encode(cp)
            try data.write(to: url, options: .atomic)
        } catch {
            // Swallow errors to avoid crashing extraction on checkpoint failure
        }
    }

    /// Load a checkpoint for the given source+destination, if any.
    static func load(source: URL, destination: URL) -> ExtractionCheckpoint? {
        let fm = FileManager.default
        let url = urlForCheckpoint(sourcePath: source.path, destinationPath: destination.path)
        if let data = try? Data(contentsOf: url), let cp = try? JSONDecoder().decode(ExtractionCheckpoint.self, from: data) {
            return cp
        }
        // Fallback: scan all and match, in case the file name schema ever changed
        let all = listAll()
        return all.first { $0.sourcePath == source.path && $0.destinationPath == destination.path }
    }

    /// Remove a checkpoint for the given source+destination.
    static func remove(source: URL, destination: URL) {
        let fm = FileManager.default
        let url = urlForCheckpoint(sourcePath: source.path, destinationPath: destination.path)
        try? fm.removeItem(at: url)
    }

    /// Enumerate all checkpoints, used at app startup/background to resume work.
    static func listAll() -> [ExtractionCheckpoint] {
        let fm = FileManager.default
        var results: [ExtractionCheckpoint] = []
        guard let items = try? fm.contentsOfDirectory(at: baseDirectory, includingPropertiesForKeys: nil) else { return [] }
        for item in items where item.pathExtension.lowercased() == "json" {
            if let data = try? Data(contentsOf: item), let cp = try? JSONDecoder().decode(ExtractionCheckpoint.self, from: data) {
                results.append(cp)
            }
        }
        return results
    }

    private static func urlForCheckpoint(sourcePath: String, destinationPath: String) -> URL {
        let safeSource = sanitizedComponent(from: sourcePath)
        let safeDest = sanitizedComponent(from: destinationPath)
        let name = "cp_\(safeSource)_to_\(safeDest).json"
        return baseDirectory.appendingPathComponent(name)
    }

    private static func sanitizedComponent(from path: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        return path.replacingOccurrences(of: "/", with: "_")
            .components(separatedBy: allowed.inverted)
            .joined()
            .prefix(60)
            .description
    }
}
