import XCTest
@testable import FolderArt

@MainActor
final class DictionaryEditorModelTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func url() -> URL { root.appendingPathComponent("suggestions-user.json") }

    func testReloadThenSaveRoundTrips() throws {
        let u = url()
        try #"[{"keys":["案件","project"],"symbol":"folder.fill","emoji":"🗂️"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u)
        m.reload()
        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.rows[0].keys, ["案件", "project"])
        XCTAssertEqual(m.rows[0].symbol, "folder.fill")
        XCTAssertTrue(m.save())
        // ファイルは loadUser で同じ項目に読める (キーは正規化されて小文字化)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
        XCTAssertEqual(dict.entries.count, 1)
        XCTAssertEqual(dict.entries[0].symbol, "folder.fill")
        XCTAssertTrue(dict.entries[0].keys.contains("project"))
    }

    func testSaveRejectsOverLimitKeysPerEntryAndKeepsFile() throws {
        let u = url()
        try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u); m.reload()
        let before = try Data(contentsOf: u)
        for n in 0...SuggestionDictionary.userMaxKeysPerEntry { m.addKey("k\(n)", to: m.rows[0].id) }
        XCTAssertFalse(m.save())
        XCTAssertNotNil(m.errorMessage)
        XCTAssertEqual(try Data(contentsOf: u), before)      // 書き換わっていない
    }

    func testEditsSetDirtyAndEmptyFileCreatedOnSave() throws {
        let u = url()                                          // ファイル無し
        let m = DictionaryEditorModel(url: u)
        XCTAssertFalse(m.isDirty)
        m.addRow(); m.addKey("メモ", to: m.rows[0].id); m.setEmoji("📝", for: m.rows[0].id)
        XCTAssertTrue(m.isDirty)
        XCTAssertTrue(m.save())
        XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
        XCTAssertEqual(dict.entries.first?.emoji, "📝")
    }

    func testExternalChangeBlocksSaveUntilForcedOrReloaded() throws {
        let u = url()
        try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u); m.reload()
        m.addRow(); m.addKey("b", to: m.rows.last!.id)
        // 外部で別内容に書き換える
        try #"[{"keys":["c"],"emoji":"🎵"}]"#.write(to: u, atomically: true, encoding: .utf8)
        XCTAssertFalse(m.save())                               // 外部変更で止まる
        XCTAssertTrue(m.pendingExternalChange)
        XCTAssertTrue(m.save(force: true))                     // 上書きは通る
        XCTAssertFalse(m.pendingExternalChange)
    }
}
