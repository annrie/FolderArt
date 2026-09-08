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
        XCTAssertNil(m.selection)                              // 保存で行が作り直されるので選択は解除される
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
        XCTAssertEqual(dict.entries.first?.emoji, "📝")
    }

    func testReloadClearsErrorMessageOnceFileBecomesReadable() throws {
        let u = url()
        try "not json".write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u)
        XCTAssertNotNil(m.errorMessage)                        // 壊れたファイルでエラー
        try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
        m.reload()
        XCTAssertNil(m.errorMessage)                           // 読めるようになったらエラーは消える
    }

    func testExternalChangeBlocksSaveUntilForcedOrReloaded() throws {
        let u = url()
        try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u); m.reload()
        m.addRow(); m.addKey("b", to: m.rows.last!.id); m.setEmoji("🎶", for: m.rows.last!.id)
        // 外部で別内容に書き換える
        try #"[{"keys":["c"],"emoji":"🎵"}]"#.write(to: u, atomically: true, encoding: .utf8)
        XCTAssertFalse(m.save())                               // 外部変更で止まる
        XCTAssertTrue(m.pendingExternalChange)
        XCTAssertTrue(m.save(force: true))                     // 上書きは通る
        XCTAssertFalse(m.pendingExternalChange)
    }

    // MARK: - isDirty は実際に変化した時だけ (レビュー修正)

    func testNoOpEditsDoNotSetDirty() throws {
        let u = url()
        try #"[{"keys":["a"],"symbol":"folder.fill","emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u); m.reload()
        XCTAssertFalse(m.isDirty)

        m.setSymbol("folder.fill", for: m.rows[0].id)          // 既存と同じ値
        XCTAssertFalse(m.isDirty)

        m.setEmoji("⭐", for: m.rows[0].id)                      // 既存と同じ値
        XCTAssertFalse(m.isDirty)

        m.removeKey("does-not-exist", from: m.rows[0].id)       // 存在しないキー
        XCTAssertFalse(m.isDirty)

        m.deleteRows([UUID()])                                  // どの行にも一致しない id
        XCTAssertFalse(m.isDirty)
        XCTAssertEqual(m.rows.count, 1)                          // 何も削除されていない
    }

    // MARK: - キーだけの不完全な行は保存前に弾く (レビュー修正)

    func testSaveBlocksRowWithKeyButNoSymbolOrEmoji() throws {
        let u = url()
        let m = DictionaryEditorModel(url: u)                    // ファイル無し
        m.addRow(); m.addKey("メモ", to: m.rows[0].id)            // キーだけ、記号も絵文字も無い
        XCTAssertFalse(m.save())
        XCTAssertNotNil(m.errorMessage)
        XCTAssertFalse(FileManager.default.fileExists(atPath: u.path))   // ファイルは作られない
    }

    func testSaveSucceedsWhenRowHasKeyAndEmoji() throws {
        let u = url()
        let m = DictionaryEditorModel(url: u)
        m.addRow(); m.addKey("メモ", to: m.rows[0].id); m.setEmoji("📝", for: m.rows[0].id)
        XCTAssertTrue(m.save())
    }

    func testSaveDropsFullyEmptyRowAlongsideValidRow() throws {
        let u = url()
        let m = DictionaryEditorModel(url: u)
        m.addRow(); m.addKey("メモ", to: m.rows[0].id); m.setEmoji("📝", for: m.rows[0].id)
        m.addRow()                                               // 完全に空の行 (＋ で足しただけ)
        XCTAssertTrue(m.save())
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
        XCTAssertEqual(dict.entries.count, 1)                    // 空の行は黙って捨てられる
    }
}
