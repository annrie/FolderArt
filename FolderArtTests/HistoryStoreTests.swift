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

    private func makeTask(folderPath: String = "/test/folder") -> IconTask {
        IconTask(
            folderPath: folderPath,
            bookmarkData: Data(),
            backupPath: "/backup/original.png",
            imageName: "test.png",
            position: .center,
            scale: 0.6,
            opacity: 0.9
        )
    }

    func testAddTaskIncreasesCount() {
        XCTAssertEqual(store.tasks.count, 0)
        store.add(makeTask())
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testNewestTaskIsFirst() {
        store.add(makeTask(folderPath: "/folder/A"))
        store.add(makeTask(folderPath: "/folder/B"))
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/B")
    }

    func testRemoveTaskDecreasesCount() {
        let task = makeTask()
        store.add(task)
        store.remove(task)
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testPersistenceAcrossInstances() {
        let task = makeTask()
        store.add(task)

        let store2 = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertEqual(store2.tasks.count, 1)
        XCTAssertEqual(store2.tasks.first?.folderPath, task.folderPath)
    }
}
