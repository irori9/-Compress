import XCTest
@testable import ArchiveManager

final class SevenZArchiveServiceTests: XCTestCase {
    func testProbeRecognizes7z() async throws {
        let svc = SevenZArchiveService()
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("test.7z")
        // 7z signature
        let sig = Data([0x37, 0x7a, 0xbc, 0xaf, 0x27, 0x1c])
        FileManager.default.createFile(atPath: tmp.path, contents: sig + Data([0,1,2,3]), attributes: nil)
        let format = await svc.probe(inputURL: tmp)
        XCTAssertEqual(format, .sevenZ)
    }

    @MainActor
    func testPasswordRequiredAndBadPassword() async throws {
        let svc = SevenZArchiveService()
        SevenZArchiveService.inspector = { _ in
            return SevenZInspectionResult(isSevenZ: true, isMultiPart: false, hasEncryptedEntries: true)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw.7z")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 0, count: 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("pw_7z_out")
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
        let svc = SevenZArchiveService()
        SevenZArchiveService.inspector = { _ in
            return SevenZInspectionResult(isSevenZ: true, isMultiPart: false, hasEncryptedEntries: false)
        }
        let tmp = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big.7z")
        FileManager.default.createFile(atPath: tmp.path, contents: Data(repeating: 1, count: 3 * 1024 * 1024), attributes: nil)
        let dest = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("big_7z_out")
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

    func testMissingVolumesDetection_7z001() async throws {
        let svc = SevenZArchiveService()
        // Create only 001
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        let p1 = dir.appendingPathComponent("multi.7z.001")
        FileManager.default.createFile(atPath: p1.path, contents: Data(repeating: 2, count: 128), attributes: nil)
        let dest = dir.appendingPathComponent("multi7z_out")
        do {
            try await svc.extract(inputURL: p1, destination: dest, password: nil, progress: { _ in }, cancellationToken: nil)
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
