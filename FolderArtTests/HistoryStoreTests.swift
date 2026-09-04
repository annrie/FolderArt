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

    /// 壊れた history.json は次の保存で消さず、.corrupt- 付きの名前で残す
    func testCorruptFileIsQuarantinedBeforeFirstSave() throws {
        try "broken".data(using: .utf8)!.write(to: tempHistoryURL)
        let s = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertNotNil(s.loadError)

        try s.upsert(makeTask())

        let dir = tempHistoryURL.deletingLastPathComponent()
        let name = tempHistoryURL.lastPathComponent
        let siblings = try FileManager.default.contentsOfDirectory(atPath: dir.path)
        let quarantined = siblings.filter { $0.hasPrefix(name + ".corrupt-") }
        XCTAssertEqual(quarantined.count, 1, "退避されたファイルが 1 つあるはず")
        defer { for f in quarantined { try? FileManager.default.removeItem(at: dir.appendingPathComponent(f)) } }
        XCTAssertEqual(try String(contentsOf: dir.appendingPathComponent(quarantined[0])), "broken")

        // 新しい history.json は正しく読める
        let reloaded = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertNil(reloaded.loadError)
        XCTAssertEqual(reloaded.tasks.count, 1)
    }

    func testUpsertReplacesRowWithSameFileIDEvenIfPathChanged() throws {
        try store.upsert(IconTask(folderPath: "/old/A", bookmarkData: Data(), backupPath: nil,
                                  overlay: .text("1"), settings: CompositionSettings(), fileID: "vol:1"))
        try store.upsert(IconTask(folderPath: "/new/A", bookmarkData: Data(), backupPath: nil,
                                  overlay: .text("2"), settings: CompositionSettings(), fileID: "vol:1"))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.folderPath, "/new/A")
        XCTAssertEqual(store.task(forFolderPath: "/gone", fileID: "vol:1")?.overlay, .text("2"))
    }

    func testUpsertInheritsBackupPathFromReplacedRow() throws {
        try store.upsert(IconTask(folderPath: "/a", bookmarkData: Data(), backupPath: "/backups/k/original.png",
                                  overlay: .text("1"), settings: CompositionSettings()))
        try store.upsert(makeTask(folderPath: "/a", overlay: .text("2")))   // backupPath nil
        XCTAssertEqual(store.tasks.first?.backupPath, "/backups/k/original.png")
        XCTAssertEqual(store.tasks.first?.overlay, .text("2"))
    }

    func testNilFileIDsNeverMatchEachOther() throws {
        try store.upsert(makeTask(folderPath: "/a"))
        try store.upsert(makeTask(folderPath: "/b"))
        XCTAssertEqual(store.tasks.count, 2)
    }

    func testReferencedAssetIDs() throws {
        let id = UUID()
        try store.upsert(makeTask(folderPath: "/a", overlay: .image(assetID: id)))
        try store.upsert(makeTask(folderPath: "/b", overlay: .text("x")))
        XCTAssertEqual(store.referencedAssetIDs, [id])
    }

    func testUpsertAllSavesOnceAndReplacesByFolder() throws {
        try store.upsert(makeTask(folderPath: "/a", overlay: .text("old")))
        let before = store.saveCount
        try store.upsertAll([makeTask(folderPath: "/a", overlay: .text("new")), makeTask(folderPath: "/b")])
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.tasks.map(\.folderPath), ["/a", "/b"])
        XCTAssertEqual(store.task(forFolderPath: "/a")?.overlay, .text("new"))
    }

    /// 同一バッチ内に同じ folderPath が複数あれば 1 行にまとめ、後の行が勝つ。
    /// 実装は「フォルダごとの最後の出現位置」の順序を保つため /b, /a の順になる
    func testUpsertAllCollapsesDuplicateFoldersWithinBatchLastWins() throws {
        let before = store.saveCount
        try store.upsertAll([
            makeTask(folderPath: "/a", overlay: .text("old")),
            makeTask(folderPath: "/b"),
            makeTask(folderPath: "/a", overlay: .text("new")),
        ])
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.tasks.map(\.folderPath), ["/b", "/a"])
        XCTAssertEqual(store.task(forFolderPath: "/a")?.overlay, .text("new"))
    }

    /// バッチ内で path が異なっても同じ fileID なら 1 行にまとめ、後の path が勝つ。
    /// 事前の history にあった行の backupPath は、生き残った行に引き継がれる
    func testUpsertAllCollapsesDuplicateFileIDsWithinBatchLastWins() throws {
        try store.upsert(IconTask(folderPath: "/old/A", bookmarkData: Data(), backupPath: "/backups/k/original.png",
                                  overlay: .text("0"), settings: CompositionSettings(), fileID: "vol:1"))
        try store.upsertAll([
            IconTask(folderPath: "/mid/A", bookmarkData: Data(), backupPath: nil,
                     overlay: .text("1"), settings: CompositionSettings(), fileID: "vol:1"),
            IconTask(folderPath: "/new/A", bookmarkData: Data(), backupPath: nil,
                     overlay: .text("2"), settings: CompositionSettings(), fileID: "vol:1"),
        ])
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.folderPath, "/new/A")
        XCTAssertEqual(store.tasks.first?.overlay, .text("2"))
        XCTAssertEqual(store.tasks.first?.backupPath, "/backups/k/original.png")
    }

    func testUpsertAllLeavesMemoryUnchangedWhenSaveFails() throws {
        let dir = tempHistoryURL.deletingLastPathComponent().appendingPathComponent("locked_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = HistoryStore(storageURL: dir.appendingPathComponent("history.json"))
        try s.upsert(makeTask(folderPath: "/keep"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        XCTAssertThrowsError(try s.upsertAll([makeTask(folderPath: "/new")]))
        XCTAssertEqual(s.tasks.map(\.folderPath), ["/keep"])
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

    /// 元のフォルダを移動した後、同じ場所に別のフォルダを作った場合: path が同じでも fileID が違えば別物
    func testSamePathWithDifferentFileIDsIsNotTheSameFolder() throws {
        let old = IconTask(folderPath: "/a", bookmarkData: Data(), backupPath: "/backups/old/original.png",
                           overlay: .symbol(name: "star.fill"), settings: CompositionSettings(), fileID: "vol:1")
        let new = IconTask(folderPath: "/a", bookmarkData: Data(), backupPath: nil,
                           overlay: .text("new"), settings: CompositionSettings(), fileID: "vol:2")
        try store.upsert(old)
        try store.upsert(new)
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.task(forFolderPath: "/a", fileID: "vol:2")?.overlay, .text("new"))
        XCTAssertNil(store.task(forFolderPath: "/a", fileID: "vol:2")?.backupPath)   // 移動した方のバックアップを継がない
        XCTAssertEqual(store.task(forFolderPath: "/a", fileID: "vol:1")?.overlay, .symbol(name: "star.fill"))
        // 片方に fileID が無ければ従来どおり path で一致する
        XCTAssertNotNil(store.task(forFolderPath: "/a", fileID: nil))
        XCTAssertNil(store.task(forFolderPath: "/b", fileID: "vol:9"))
    }


    /// 一括適用の途中で終了しても、控え (ジャーナル) に残った行は次の起動で履歴へ取り込まれる
    func testRecoversPendingJournalOnInit() throws {
        try store.upsert(makeTask(folderPath: "/kept"))
        let pending = [makeTask(folderPath: "/p1"), makeTask(folderPath: "/p2", overlay: .text("t"))]
        try store.journal(pending)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.journalURL.path))
        let reopened = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertEqual(Set(reopened.tasks.map(\.folderPath)), ["/kept", "/p1", "/p2"])
        XCTAssertFalse(FileManager.default.fileExists(atPath: reopened.journalURL.path))
        XCTAssertNil(reopened.loadError)
        // 履歴が読めない起動では取り込まず、控えも残す (数行だけの履歴を書いてしまわない)
        try store.journal(pending)
        try Data("broken".utf8).write(to: tempHistoryURL)
        let broken = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertNotNil(broken.loadError)
        XCTAssertTrue(broken.tasks.isEmpty)
        XCTAssertTrue(FileManager.default.fileExists(atPath: broken.journalURL.path))
        try? FileManager.default.removeItem(at: broken.journalURL)
    }


    func testPendingJournalReturnsRowsLeftUnrecovered() throws {
        XCTAssertTrue(store.pendingJournal().isEmpty)
        try store.journal([makeTask(folderPath: "/p1"), makeTask(folderPath: "/p2")])
        XCTAssertEqual(store.pendingJournal().map(\.folderPath), ["/p1", "/p2"])
        store.clearJournal()
        XCTAssertTrue(store.pendingJournal().isEmpty)
    }

}
