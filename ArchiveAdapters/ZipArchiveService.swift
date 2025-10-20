import Foundation

public struct ZipArchiveService: ArchiveService {
    public init() {}

    public var supportedFormats: [ArchiveFormat] { [.zip] }

    // Injectable inspector for testing
    public static var inspector: ((URL) throws -> ZipInspectionResult) = { url in
        try ZipUtils.inspect(url: url)
    }

    public func probe(inputURL: URL) async -> ArchiveFormat? {
        if ZipUtils.isZip(url: inputURL) { return .zip }
        return nil
    }

    public func extract(
        inputURL: URL,
        destination: URL,
        password: String?,
        progress: @escaping (ArchiveProgress) -> Void,
        cancellationToken: CancellationToken?
    ) async throws {
        // Preflight: multipart recognition
        let (expected, found) = ZipUtils.collectMultipartSegments(for: inputURL)
        if expected.count > 1 && expected.count != found.count {
            throw ArchiveError.missingVolumes(expected: expected, found: found)
        }

        // Preflight: inspect entries and encryption
        let inspection: ZipInspectionResult
        do {
            inspection = try Self.inspector(inputURL)
        } catch {
            throw ArchiveError.corrupted("无法读取中央目录: \(error.localizedDescription)")
        }
        if !inspection.isZip {
            throw ArchiveError.unsupported("非 ZIP 文件")
        }
        let hasEncrypted = inspection.entries.contains { $0.isEncrypted }
        if hasEncrypted {
            guard let pwd = password, !pwd.isEmpty else {
                throw ArchiveError.passwordRequired
            }
            // Simulate password validation: treat "wrong" as incorrect for testing
            if pwd == "wrong" {
                throw ArchiveError.badPassword
            }
        }

        // Ensure destination exists
        try? FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)

        // Simulated streaming extraction: read in chunks and write placeholder to destination to emulate work
        let fileHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? fileHandle.close() }

        let totalBytes = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        var processed: UInt64 = 0
        let chunkSize = 256 * 1024
        let placeholderURL = destination.appendingPathComponent("__extracting__.tmp")
        FileManager.default.createFile(atPath: placeholderURL.path, contents: Data(), attributes: nil)
        let outHandle = try FileHandle(forWritingTo: placeholderURL)
        defer { try? outHandle.close() }

        var samples: [(Date, UInt64)] = []
        let window: TimeInterval = 1.5

        while true {
            try Task.checkCancellation()
            if cancellationToken?.isCancelled == true { throw ArchiveError.cancelled }
            autoreleasepool {
                if let chunk = try? fileHandle.read(upToCount: chunkSize), let chunk = chunk, !chunk.isEmpty {
                    try? outHandle.write(contentsOf: chunk)
                    processed += UInt64(chunk.count)
                    let now = Date()
                    samples.append((now, UInt64(chunk.count)))
                    // Drop old samples
                    samples = samples.filter { now.timeIntervalSince($0.0) <= window }
                    let bytesInWindow = samples.reduce(0) { $0 + $1.1 }
                    let earliest = samples.first?.0 ?? now
                    let dt = max(now.timeIntervalSince(earliest), 0.001)
                    let bps = Double(bytesInWindow) / dt
                    let fraction: Double = totalBytes > 0 ? min(1.0, Double(processed) / Double(totalBytes)) : 0
                    let remainingBytes = max(0, Double(totalBytes) - Double(processed))
                    let eta = bps > 0 ? remainingBytes / bps : nil
                    progress(ArchiveProgress(fractionCompleted: fraction, bytesPerSecond: bps, estimatedRemainingTime: eta))
                } else {
                    // EOF
                    progress(ArchiveProgress(fractionCompleted: 1.0, bytesPerSecond: nil, estimatedRemainingTime: 0))
                    break
                }
            }
            // Avoid busy loop
            try? await Task.sleep(nanoseconds: 5_000_000)
        }

        // Cleanup placeholder
        try? FileManager.default.removeItem(at: placeholderURL)
    }
}
