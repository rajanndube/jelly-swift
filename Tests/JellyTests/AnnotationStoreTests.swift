import XCTest
@testable import Jelly

/// 7-day TTL parity with `dev.jelly.storage.AnnotationStore`. Stale entries
/// are filtered on read; empty saves clear the key.
final class AnnotationStoreTests: XCTestCase {

    private var suite: String!
    private var store: AnnotationStore!

    override func setUp() {
        super.setUp()
        suite = "dev.jelly.tests.\(UUID().uuidString)"
        store = AnnotationStore(suiteName: suite)
    }

    override func tearDown() {
        if let s = suite { UserDefaults().removePersistentDomain(forName: s) }
        suite = nil
        store = nil
        super.tearDown()
    }

    func test_saveAndLoad_roundTrip() {
        let a = Annotation(id: "x", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs())
        store.save(screenKey: "S", annotations: [a])
        XCTAssertEqual(store.load(screenKey: "S").map(\.id), ["x"])
    }

    func test_load_filtersAnnotationsOlderThanSevenDays() {
        let stale = Annotation(id: "old", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs() - eightDays())
        let fresh = Annotation(id: "new", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs())
        store.save(screenKey: "S", annotations: [stale, fresh])
        XCTAssertEqual(store.load(screenKey: "S").map(\.id), ["new"])
    }

    func test_save_emptyArray_clearsTheKey() {
        let a = Annotation(id: "x", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs())
        store.save(screenKey: "S", annotations: [a])
        store.save(screenKey: "S", annotations: [])
        XCTAssertTrue(store.load(screenKey: "S").isEmpty)
    }

    func test_perScreen_isolation() {
        let a = Annotation(id: "x", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs())
        let b = Annotation(id: "y", x: 0, y: 0, comment: "c", element: "e", elementPath: "p", timestamp: nowMs())
        store.save(screenKey: "S1", annotations: [a])
        store.save(screenKey: "S2", annotations: [b])
        XCTAssertEqual(store.load(screenKey: "S1").map(\.id), ["x"])
        XCTAssertEqual(store.load(screenKey: "S2").map(\.id), ["y"])
    }

    private func nowMs() -> Int64 { Int64(Date().timeIntervalSince1970 * 1000) }
    private func eightDays() -> Int64 { 8 * 24 * 60 * 60 * 1000 }
}
