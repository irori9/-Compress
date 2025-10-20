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

    func testPathSecurityRejectsAbsoluteAndTraversal() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("root")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        XCTAssertThrowsError(try PathSecurity.sanitizedURL(forArchiveEntry: "/etc/passwd", destinationRoot: root))
        XCTAssertThrowsError(try PathSecurity.sanitizedURL(forArchiveEntry: "..../secret.txt", destinationRoot: root))
        XCTAssertThrowsError(try PathSecurity.sanitizedURL(forArchiveEntry: "../../secret.txt", destinationRoot: root))
        XCTAssertThrowsError(try PathSecurity.sanitizedURL(forArchiveEntry: "C:/windows/system32", destinationRoot: root))
    }

    func testPathSecurityInsideRoot() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("root2")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let out = try PathSecurity.sanitizedURL(forArchiveEntry: "folder/file.txt", destinationRoot: root)
        XCTAssertTrue(PathSecurity.isInsideRoot(out, root: root))
        XCTAssertEqual(out.deletingLastPathComponent().lastPathComponent, "folder")
    }

    func testRenamePolicy() throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("rename_root")
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let f1 = root.appendingPathComponent("a.txt")
        FileManager.default.createFile(atPath: f1.path, contents: Data(), attributes: nil)
        let next = PathSecurity.nextAvailableURL(for: f1, policy: .rename)
        XCTAssertNotEqual(next.path, f1.path)
        XCTAssertTrue(next.lastPathComponent.contains("a"))
    }
}
