import XCTest
@testable import FolderArt

final class SuggestionDictionaryTests: XCTestCase {

    func testBundledDictionaryLoadsAndIsWellFormed() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        XCTAssertGreaterThanOrEqual(dict.entries.count, 90)
        for entry in dict.entries {
            XCTAssertFalse(entry.keys.isEmpty)
            XCTAssertTrue(entry.symbol != nil || entry.emoji != nil, "\(entry.keys)")
            for key in entry.keys {
                XCTAssertEqual(key, key.lowercased(), "keys must be lowercase: \(key)")
                // 日本語 (非 ASCII) のキーは 2 文字以上 (誤爆防止)
                if key.unicodeScalars.contains(where: { !$0.isASCII }) {
                    XCTAssertGreaterThanOrEqual(key.count, 2, "Japanese key too short: \(key)")
                }
            }
        }
    }

    func testEverySymbolExistsInCatalogAndIsNotRestricted() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        let names = Set(SymbolCatalog.shared.names)
        for entry in dict.entries {
            if let symbol = entry.symbol {
                XCTAssertTrue(names.contains(symbol), "unknown or restricted symbol: \(symbol)")
            }
        }
    }

    func testMissingResourceGivesEmptyDictionary() {
        let dict = SuggestionDictionary.load(bundle: Bundle(path: "/nonexistent") ?? Bundle(for: SuggestionDictionaryTests.self),
                                             resourceName: "does-not-exist")
        XCTAssertEqual(dict, .empty)
    }

    func testNoKeyAppearsInMultipleEntries() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        var keyToCount: [String: Int] = [:]
        for entry in dict.entries {
            for key in entry.keys {
                keyToCount[key, default: 0] += 1
            }
        }
        for (key, count) in keyToCount {
            XCTAssertEqual(count, 1, "key appears in multiple entries: \(key)")
        }
    }

    /// 中身からの提案は辞書の代表キーで記号・絵文字を引く。folder 以外の全種類が引けて、記号と絵文字の両方を持つ
    func testEveryContentKindHasADictionaryEntry() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        for kind in ContentKind.allCases {
            guard let key = kind.dictionaryKey else { XCTAssertEqual(kind, .folder); continue }
            let entry = dict.entry(forKey: key)
            XCTAssertNotNil(entry, "no entry for \(kind) (key \(key))")
            XCTAssertNotNil(entry?.symbol, "\(kind)")
            XCTAssertNotNil(entry?.emoji, "\(kind)")
        }
        XCTAssertNil(dict.entry(forKey: "no-such-key"))
    }

    // MARK: - ユーザー辞書

    private func entry(_ keys: [String], symbol: String? = "star.fill", emoji: String? = "⭐") -> SuggestionEntry {
        SuggestionEntry(keys: keys, symbol: symbol, emoji: emoji)
    }

    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SuggestionDictionaryTests_\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMergingUserWinsAndBundledLosesOverriddenKeys() {
        let bundled = SuggestionDictionary(entries: [
            entry(["photo", "photos"], symbol: "photo.fill", emoji: "📷"),
            entry(["music"], symbol: "music.note", emoji: "🎵"),
        ])
        let user = SuggestionDictionary(entries: [entry(["photo", "pics"], symbol: "camera.fill", emoji: "📸")])
        let merged = SuggestionDictionary.merging(user: user, bundled: bundled)
        XCTAssertEqual(merged.entries.count, 3)
        XCTAssertEqual(merged.entries[0].keys, ["photo", "pics"])          // ユーザーが先頭
        XCTAssertEqual(merged.entries[1].keys, ["photos"])                 // 同梱から photo が外れる
        XCTAssertEqual(merged.entries[2].keys, ["music"])                  // 無関係な項目はそのまま
        XCTAssertEqual(merged.entry(forKey: "photo")?.symbol, "camera.fill")
        // 合成後もキーは 1 項目にしか現れない
        let all = merged.entries.flatMap(\.keys)
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testMergingDropsBundledEntriesLeftWithoutKeys() {
        let bundled = SuggestionDictionary(entries: [entry(["pdf"], symbol: "doc.richtext.fill", emoji: "📄")])
        let user = SuggestionDictionary(entries: [entry(["pdf"], symbol: "doc.fill", emoji: nil)])
        let merged = SuggestionDictionary.merging(user: user, bundled: bundled)
        XCTAssertEqual(merged.entries.map(\.keys), [["pdf"]])
        XCTAssertEqual(merged.entries[0].symbol, "doc.fill")
    }

    func testMergingWithEmptyUserIsBundled() {
        let bundled = SuggestionDictionary(entries: [entry(["a"]), entry(["b"])])
        XCTAssertEqual(SuggestionDictionary.merging(user: .empty, bundled: bundled), bundled)
    }

    func testLoadUserReturnsNilWhenAbsent() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).json")
        XCTAssertNil(SuggestionDictionary.loadUser(at: url))
    }

    func testLoadUserMalformedIsFailure() throws {
        let url = try write("{ not json")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.malformed = error else { return XCTFail("expected malformed, got \(error)") }
    }

    func testLoadUserNormalizesKeysAndDedupes() throws {
        let url = try write("""
        [
          {"keys": ["Ｐｈｏｔｏ", " photo ", "PHOTO", "", "旅行"], "symbol": "camera.fill", "emoji": ""},
          {"keys": ["photo", "trip"], "symbol": "", "emoji": "✈️"},
          {"keys": ["nothing"], "symbol": "", "emoji": ""},
          {"keys": ["   "], "symbol": "star.fill"}
        ]
        """)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected success") }
        XCTAssertEqual(dict.entries.count, 2)
        XCTAssertEqual(dict.entries[0].keys, ["photo", "旅行"])      // 全角→半角、小文字化、前後の空白、重複、空を整理
        XCTAssertEqual(dict.entries[0].symbol, "camera.fill")
        XCTAssertNil(dict.entries[0].emoji)                        // 空文字は nil
        XCTAssertEqual(dict.entries[1].keys, ["trip"])             // 項目間の重複は先勝ち
        XCTAssertEqual(dict.entries[1].emoji, "✈️")
        XCTAssertNil(dict.entries[1].symbol)
        // "nothing" は symbol も emoji も無いので捨てる、"   " はキーが空になるので捨てる
    }

    func testLoadUserRejectsOversizedInput() throws {
        let many = (0..<(SuggestionDictionary.userMaxEntries + 1)).map { #"{"keys": ["k\#($0)"], "emoji": "⭐"}"# }.joined(separator: ",")
        let url = try write("[\(many)]")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? UserDictionaryError, .tooManyEntries(SuggestionDictionary.userMaxEntries + 1))

        let longKey = String(repeating: "a", count: SuggestionDictionary.userMaxKeyLength + 1)
        let url2 = try write(#"[{"keys": ["\#(longKey)"], "emoji": "⭐"}]"#)
        guard case .failure(let error2)? = SuggestionDictionary.loadUser(at: url2) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.keyTooLong = error2 else { return XCTFail("expected keyTooLong, got \(error2)") }

        let manyKeys = (0..<(SuggestionDictionary.userMaxKeysPerEntry + 1)).map { "\"k\($0)\"" }.joined(separator: ",")
        let url3 = try write(#"[{"keys": [\#(manyKeys)], "emoji": "⭐"}]"#)
        guard case .failure(let error3)? = SuggestionDictionary.loadUser(at: url3) else { return XCTFail("expected failure") }
        XCTAssertEqual(error3 as? UserDictionaryError, .tooManyKeys(SuggestionDictionary.userMaxKeysPerEntry + 1))
    }

    func testLoadUserRejectsFileOverOneMegabyte() throws {
        // 1 MB + 1 バイトの JSON (空白で水増し)。読む前にサイズで弾く
        let padding = String(repeating: " ", count: SuggestionDictionary.userMaxFileBytes + 1)
        let url = try write("[\(padding)]")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.tooLarge = error else { return XCTFail("expected tooLarge, got \(error)") }
    }

    func testUserTemplateIsValidAndLoadable() throws {
        let url = try write(SuggestionDictionary.userTemplate)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("template must load") }
        XCTAssertEqual(dict.entries.count, 1)
        XCTAssertEqual(dict.entries[0].keys, ["example", "サンプル"])
    }

    func testUserDictionaryErrorsAreLocalized() {
        for error in [UserDictionaryError.tooLarge(1), .tooManyEntries(2), .tooManyKeys(3), .keyTooLong("k"), .symbolTooLong("s"), .emojiTooLong("e"), .malformed("m")] {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
    }
}
