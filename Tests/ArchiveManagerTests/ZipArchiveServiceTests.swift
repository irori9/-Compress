import XCTest
@testable import ArchiveManager

final class ZipArchiveServiceTests: XCTestCase {
    func testProbeRecognizesZip() async throws {
        let svc = ZipArchiveService()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.zip")
        FileManager.default.createFile(atPath: tmp.path, contents: Data([0x50, 0x4b, 0x05, 0x06]), attributes: nil)
        let format = await svc.probe(inputURL: tmp)
        XCTAssertEqual(format, .zip)
    }

    @MainActor
    func testPasswordRequiredAndBadPassword() async throws {
        let svc = ZipArchiveService()
        // Inject inspector that reports an encrypted entry
        ZipArchiveService.inspector = { _ in
            let entry = ZipCentralDirectoryEntry(isEncrypted: true, uncompressedSize: 100, fileName: "file.txt")
            return ZipInspectionResult(isZip: true, isMultiPart: false, entries: [entry], totalUncompressedSize: 100)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw.zip")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 0, count: 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw_out")
        do {
            try await svc.extract(inputURL: tmp, destination: dest, password: nil, progress: { _ in }, cancellationToken: nil)
            XCTFail("expected passwordRequired")
        } catch let err as ArchiveError {
            switch err {
            case .passwordRequired:
                break
            default:
                XCTFail("unexpected error: \(err)")
            }
        }
        do {
            try await svc.extract(inputURL: tmp, destination: dest, password: "wrong", progress: { _ in }, cancellationToken: nil)
            XCTFail("expected badPassword")
        } catch let err as ArchiveError {
            switch err {
            case .badPassword:
                break
            default:
                XCTFail("unexpected error: \(err)")
            }
        }
    }

    @MainActor
    func testProgressAndCancel() async throws {
        let svc = ZipArchiveService()
        // Inspector reports non-encrypted entries
        ZipArchiveService.inspector = { _ in
            return ZipInspectionResult(isZip: true, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big.zip")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 1, count: 5 * 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big_out")
        let token = CancellationToken()
        var sawProgress = false
        let t = Task {
            do {
                try await svc.extract(inputURL: tmp, destination: dest, password: nil, progress: { p in
                    if p.fractionCompleted > 0 {
                        sawProgress = true
                        token.cancel()
                    }
                }, cancellationToken: token)
                XCTFail("expected cancel")
            } catch let err as ArchiveError {
                switch err {
                case .cancelled:
                    break
                default:
                    XCTFail("unexpected error: \(err)")
                }
            } catch is CancellationError {
                // accept
            } catch {
                XCTFail("unexpected error: \(error)")
            }
        }
        _ = await t.result
        XCTAssertTrue(sawProgress)
    }

    @MainActor
    func testResumableAfterCancelAndThenComplete() async throws {
        let svc = ZipArchiveService()
        ZipArchiveService.inspector = { _ in
            return ZipInspectionResult(isZip: true, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("resume.zip")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 2, count: 3 * 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("resume_out")

        // First run: cancel after some progress
        let token1 = CancellationToken()
        var firstProgress: Double = 0
        let cancelTask = Task {
            do {
                try await svc.extract(inputURL: tmp, destination: dest, password: nil, progress: { p in
                    firstProgress = p.fractionCompleted
                    if firstProgress > 0.1 { token1.cancel() }
                }, cancellationToken: token1)
                XCTFail("expected cancel")
            } catch { /* expected */ }
        }
        _ = await cancelTask.result
        XCTAssertGreaterThan(firstProgress, 0)
        // Check that a checkpoint exists
        let cps1 = ExtractionCheckpointStore.listAll()
        XCTAssertTrue(cps1.contains(where: { $0.sourcePath == tmp.path && $0.destinationPath == dest.path }))

        // Second run: should resume and complete
        try await svc.extract(inputURL: tmp, destination: dest, password: nil, progress: { _ in }, cancellationToken: nil)
        let cps2 = ExtractionCheckpointStore.listAll()
        XCTAssertFalse(cps2.contains(where: { $0.sourcePath == tmp.path && $0.destinationPath == dest.path }))
    }
}
