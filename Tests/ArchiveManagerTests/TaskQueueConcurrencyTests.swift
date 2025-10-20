import XCTest
@testable import ArchiveManager

final class TaskQueueConcurrencyTests: XCTestCase {
    @MainActor
    func testConcurrencyLimitPauseResume() async throws {
        // Inspector reports non-encrypted entries for speed
        ZipArchiveService.inspector = { _ in
            return ZipInspectionResult(isZip: true, isMultiPart: false, entries: [], totalUncompressedSize: 0)
        }
        let queue = TaskQueue()
        queue.maxConcurrentTasks = 2
        // Create three big files
        let dir = URL(fileURLWithPath: NSTemporaryDirectory())
        var urls: [URL] = []
        for i in 0..<3 {
            let u = dir.appendingPathComponent("conc_\(i).zip")
            FileManager.default.createFile(atPath: u.path, contents: Data(repeating: 7, count: 5 * 1024 * 1024), attributes: nil)
            urls.append(u)
        }
        _ = queue.addTask(from: urls[0])
        _ = queue.addTask(from: urls[1])
        _ = queue.addTask(from: urls[2])
        queue.schedule()
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1s
        let running1 = queue.tasks.filter { $0.state == .running }.count
        XCTAssertLessThanOrEqual(running1, 2)
        // Pause one running task
        if let t = queue.tasks.first(where: { $0.state == .running }) {
            queue.pause(taskID: t.id)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let running2 = queue.tasks.filter { $0.state == .running }.count
        XCTAssertLessThanOrEqual(running2, 2)
        // Resume paused
        if let t = queue.tasks.first(where: { $0.state == .paused }) {
            queue.resume(taskID: t.id)
        }
        try? await Task.sleep(nanoseconds: 100_000_000)
        let running3 = queue.tasks.filter { $0.state == .running }.count
        XCTAssertLessThanOrEqual(running3, 2)
    }
}
