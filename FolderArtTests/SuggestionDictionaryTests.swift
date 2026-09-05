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
}
