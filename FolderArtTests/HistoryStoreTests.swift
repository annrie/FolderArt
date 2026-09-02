import XCTest
@testable import FolderArt

final class HistoryStoreTests: XCTestCase {

    private var tempHistoryURL: URL!
    private var store: HistoryStore!

    override func setUp() {
        super.setUp()
        tempHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history_test_\(UUID().uuidString).json")
        store = HistoryStore(storageURL: tempHistoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHistoryURL)
        super.tearDown()
    }

    private func makeTask(folderPath: String = "/test/folder",
                          overlay: Overlay = .symbol(name: "star.fill")) -> IconTask {
        IconTask(folderPath: folderPath, bookmarkData: Data(), backupPath: nil,
                 overlay: overlay, settings: CompositionSettings())
    }

    func testUpsertIncreasesCount() throws {
        XCTAssertEqual(store.tasks.count, 0)
        try store.upsert(makeTask())
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testNewestTaskIsFirst() throws {
        try store.upsert(makeTask(folderPath: "/folder/A"))
        try store.upsert(makeTask(folderPath: "/folder/B"))
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/B")
    }

    func testUpsertReplacesSameFolder() throws {
        try store.upsert(makeTask(folderPath: "/folder/A", overlay: .text("1")))
        try store.upsert(makeTask(folderPath: "/folder/B"))
        try store.upsert(makeTask(folderPath: "/folder/A", overlay: .text("2")))
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/A")
        XCTAssertEqual(store.tasks.first?.overlay, .text("2"))
        XCTAssertEqual(store.task(forFolderPath: "/folder/A")?.overlay, .text("2"))
    }

    func testRemoveTaskDecreasesCount() throws {
        let task = makeTask()
        try store.upsert(task)
        try store.remove(task)
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testPersistenceAcrossInstances() throws {
        let task = makeTask()
        try store.upsert(task)
        let store2 = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertEqual(store2.tasks.count, 1)
        XCTAssertEqual(store2.tasks.first?.folderPath, task.folderPath)
        XCTAssertNil(store2.loadError)
    }

    func testCorruptFileSetsLoadErrorAndStartsEmpty() throws {
        try "broken".data(using: .utf8)!.write(to: tempHistoryURL)
        let s = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertNotNil(s.loadError)
        XCTAssertTrue(s.tasks.isEmpty)
    }

    func testReferencedAssetIDs() throws {
        let id = UUID()
        try store.upsert(makeTask(folderPath: "/a", overlay: .image(assetID: id)))
        try store.upsert(makeTask(folderPath: "/b", overlay: .text("x")))
        XCTAssertEqual(store.referencedAssetIDs, [id])
    }
}
