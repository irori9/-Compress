import XCTest
@testable import ArchiveManager

final class ArchiveManagerTests: XCTestCase {
    @MainActor func testAddTask() {
        let queue = TaskQueue()
        let url = URL(fileURLWithPath: "/tmp/demo.zip")
        let task = queue.addTask(from: url)
        XCTAssertEqual(queue.tasks.count, 1)
        XCTAssertEqual(task.sourceURL, url)
        XCTAssertEqual(task.state, .pending)
    }
}
