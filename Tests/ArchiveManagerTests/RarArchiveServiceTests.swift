import XCTest
@testable import ArchiveManager

final class RarArchiveServiceTests: XCTestCase {
    func testProbeRecognizesRar() async throws {
        let svc = RarArchiveService()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.rar")
        // Write RAR5 signature
        let sig = Data([0x52, 0x61, 0x72, 0x21, 0x1a, 0x07, 0x01, 0x00])
        FileManager.default.createFile(atPath: tmp.path, contents: sig + Data([0,1,2,3]), attributes: nil)
        let format = await svc.probe(inputURL: tmp)
        XCTAssertEqual(format, .rar)
    }

    @MainActor
    func testPasswordRequiredAndBadPassword() async throws {
        var svc = RarArchiveService()
        // Inject inspector that reports encrypted entries
        RarArchiveService.inspector = { _ in
            return RarInspectionResult(isRar: true, isMultiPart: false, hasEncryptedEntries: true)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw.rar")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 0, count: 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw_rar_out")
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
        let svc = RarArchiveService()
        // Inspector reports non-encrypted
        RarArchiveService.inspector = { _ in
            return RarInspectionResult(isRar: true, isMultiPart: false, hasEncryptedEntries: false)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big.rar")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 1, count: 3 * 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big_rar_out")
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

    func testMissingVolumesDetection_r00Style() async throws {
        let svc = RarArchiveService()
        // Create only r00 without .rar
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let r00 = dir.appendingPathComponent("mvtest.r00")
        FileManager.default.createFile(atPath: r00.path, contents: Data(repeating: 2, count: 128), attributes: nil)
        let dest = dir.appendingPathComponent("mvtest_out")
        do {
            try await svc.extract(inputURL: r00, destination: dest, password: nil, progress: { _ in }, cancellationToken: nil)
            XCTFail("expected missingVolumes")
        } catch let err as ArchiveError {
            switch err {
            case .missingVolumes(let expected, let found):
                XCTAssertTrue(expected.count > found.count)
            default:
                XCTFail("unexpected error: \(err)")
            }
        }
    }
}
