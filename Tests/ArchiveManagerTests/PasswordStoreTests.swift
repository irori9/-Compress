import XCTest
@testable import ArchiveManager

final class PasswordStoreTests: XCTestCase {
    func testSetGetAndClear() throws {
        let store = PasswordStore.shared
        store.clearAll()
        let url = URL(fileURLWithPath: "/tmp/psw.zip")
        XCTAssertNil(store.password(for: .file(url)))
        store.setPassword("123", for: .file(url))
        XCTAssertEqual(store.password(for: .file(url)), "123")
        store.clearAll()
        XCTAssertNil(store.password(for: .file(url)))
    }
}
