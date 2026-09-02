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

    func testResaveFailureKeepsLoadedTasksAndSetsLoadError() throws {
        try store.upsert(makeTask())
        // 保存先を書き込み不可にして再読み込み → 読めた 1 件は残り、loadError が立つ
        let dir = tempHistoryURL.deletingLastPathComponent()
        let lockedDir = dir.appendingPathComponent("locked_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: lockedDir, withIntermediateDirectories: true)
        let lockedURL = lockedDir.appendingPathComponent("history.json")
        try FileManager.default.copyItem(at: tempHistoryURL, to: lockedURL)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: lockedDir.path)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: lockedDir.path)
            try? FileManager.default.removeItem(at: lockedDir)
        }
        let s = HistoryStore(storageURL: lockedURL)
        XCTAssertEqual(s.tasks.count, 1)
        XCTAssertNotNil(s.loadError)
    }
}
