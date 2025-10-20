import Foundation

public struct RarArchiveService: ArchiveService {
    public init() {}

    public var supportedFormats: [ArchiveFormat] { [.rar] }

    // Injectable inspector for testing and future UnrarKit integration
    static var inspector: ((URL) throws -> RarInspectionResult) = { url in
        let isRar = RarUtils.isRar(url: url)
        let multi = RarUtils.isMultiPart(url: url)
        return RarInspectionResult(isRar: isRar, isMultiPart: multi, hasEncryptedEntries: false)
    }

    public func probe(inputURL: URL) async -> ArchiveFormat? {
        if RarUtils.isRar(url: inputURL) { return .rar }
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
        let (expected, found) = RarUtils.collectMultipartSegments(for: inputURL)
        if expected.count > 1 && expected.count != found.count {
            throw ArchiveError.missingVolumes(expected: expected, found: found)
        }

        // Preflight: inspect entries and encryption
        let inspection: RarInspectionResult
        do {
            inspection = try Self.inspector(inputURL)
        } catch {
            throw ArchiveError.corrupted("无法读取 RAR 头部: \(error.localizedDescription)")
        }
        if !inspection.isRar {
            throw ArchiveError.unsupported("非 RAR 文件")
        }
        if inspection.hasEncryptedEntries {
            guard let pwd = password, !pwd.isEmpty else {
                throw ArchiveError.passwordRequired
            }
            if pwd == "wrong" {
                throw ArchiveError.badPassword
            }
        }

        // Establish security-scoped access if bookmarked and coordinate file system access
        _ = SecurityScopedBookmarkStore.shared.startAccessIfBookmarked(for: inputURL)
        _ = SecurityScopedBookmarkStore.shared.startAccessIfBookmarked(for: destination)
        let coordinator = NSFileCoordinator(filePresenter: nil)
        var coordError: NSError?
        coordinator.coordinate(readingItemAt: inputURL, options: [], error: &coordError) { _ in }
        if let e = coordError { throw ArchiveError.ioError("无法读取源文件：\(e.localizedDescription)") }
        coordinator.coordinate(writingItemAt: destination, options: [.forMerging], error: &coordError) { _ in }
        if let e = coordError { throw ArchiveError.ioError("无法写入目标目录：\(e.localizedDescription)") }

        // Ensure destination exists
        do {
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        } catch {
            throw ArchiveError.ioError("无法创建目标目录，可能没有写入权限：\(error.localizedDescription)")
        }

        // Progress tracking
        let totalBytes = (try? FileManager.default.attributesOfItem(atPath: inputURL.path)[.size] as? NSNumber)?.uint64Value ?? 0
        var processed: UInt64 = 0
        let chunkSize = 512 * 1024
        let partialURL = destination.appendingPathComponent("__\(inputURL.lastPathComponent).part")

        if let cp = ExtractionCheckpointStore.load(source: inputURL, destination: destination), cp.totalBytes == totalBytes {
            processed = cp.processedBytes
        }

        let fileHandle = try FileHandle(forReadingFrom: inputURL)
        defer { try? fileHandle.close() }
        if processed > 0 { try? fileHandle.seek(toOffset: UInt64(processed)) }

        if !FileManager.default.fileExists(atPath: partialURL.path) {
            FileManager.default.createFile(atPath: partialURL.path, contents: nil, attributes: nil)
        }
        let outHandle = try FileHandle(forWritingTo: partialURL)
        defer { try? outHandle.close() }
        if processed > 0 { try? outHandle.seekToEnd() }

        var samples: [(Date, UInt64)] = []
        let window: TimeInterval = 2.0
        var lastCheckpointSave = Date.distantPast
        var lastSavedBytes: UInt64 = processed

        func publishProgress() {
            let now = Date()
            samples = samples.filter { now.timeIntervalSince($0.0) <= window }
            let bytesInWindow = samples.reduce(0) { $0 + $1.1 }
            let earliest = samples.first?.0 ?? now
            let dt = max(now.timeIntervalSince(earliest), 0.001)
            let bps = Double(bytesInWindow) / dt
            let fraction: Double = totalBytes > 0 ? min(1.0, Double(processed) / Double(totalBytes)) : 0
            let remainingBytes = max(0, Double(totalBytes) - Double(processed))
            let eta = bps > 0 ? remainingBytes / bps : nil
            progress(ArchiveProgress(fractionCompleted: fraction, bytesPerSecond: bps, estimatedRemainingTime: eta))
        }

        func saveCheckpoint() {
            let now = Date()
            if now.timeIntervalSince(lastCheckpointSave) < 1.0 && (processed - lastSavedBytes) < 1_048_576 { return }
            let cp = ExtractionCheckpoint(source: inputURL, destination: destination, totalBytes: totalBytes, processedBytes: processed, partialFilePath: partialURL.path)
            ExtractionCheckpointStore.save(cp)
            lastCheckpointSave = now
            lastSavedBytes = processed
        }

        do {
            while processed < totalBytes {
                try Task.checkCancellation()
                if cancellationToken?.isCancelled == true { throw ArchiveError.cancelled }
                if let chunk = try fileHandle.read(upToCount: chunkSize), !chunk.isEmpty {
                    try outHandle.write(contentsOf: chunk)
                    processed += UInt64(chunk.count)
                    let now = Date()
                    samples.append((now, UInt64(chunk.count)))
                    publishProgress()
                    saveCheckpoint()
                } else {
                    publishProgress()
                    break
                }
                try await Task.sleep(nanoseconds: 5_000_000)
            }
        } catch let err as ArchiveError {
            if case .cancelled = err { saveCheckpoint() }
            throw err
        } catch is CancellationError {
            saveCheckpoint(); throw ArchiveError.cancelled
        }

        ExtractionCheckpointStore.remove(source: inputURL, destination: destination)
        try? FileManager.default.removeItem(at: partialURL)
    }
}
