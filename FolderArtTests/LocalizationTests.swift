import XCTest
@testable import FolderArt

/// ビルド済みバンドルの .lproj を見る (サンドボックスからソースツリーは読めない)。
/// どの言語のプロセスで走っても通るよう、比較は英語の .lproj を Bundle として直接開いて行う。
final class LocalizationTests: XCTestCase {
    static let languages = ["ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"]

    /// Localizable.strings と Localizable.stringsdict (単複の variation はこちらに出る) を合わせたキー → 値
    private func table(_ name: String, language: String) -> [String: Any] {
        var merged: [String: Any] = [:]
        for ext in ["strings", "stringsdict"] {
            if let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: nil, forLocalization: language),
               let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
                merged.merge(dict) { a, _ in a }
            }
        }
        return merged
    }

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
        return try XCTUnwrap(Bundle(path: path), language)
    }

    func testEveryLanguageHasEveryKey() {
        let ja = table("Localizable", language: "ja")
        XCTAssertGreaterThan(ja.count, 100)
        for language in Self.languages {
            let keys = Set(table("Localizable", language: language).keys)
            XCTAssertEqual(keys, Set(ja.keys), "\(language): missing \(Set(ja.keys).subtracting(keys).sorted()) extra \(keys.subtracting(ja.keys).sorted())")
        }
    }

    func testJapaneseValuesEqualTheirKeys() {
        for (key, value) in table("Localizable", language: "ja") {
            XCTAssertEqual(value as? String, key)
        }
    }

    func testEnglishValuesAreTranslated() throws {
        let en = try bundle(for: "en")
        XCTAssertEqual(en.localizedString(forKey: "履歴", value: nil, table: nil), "History")
        XCTAssertEqual(en.localizedString(forKey: "配置:", value: nil, table: nil), "Position:")
        XCTAssertEqual(String(localized: "上\(5)%", bundle: en, locale: Locale(identifier: "en")), "Up 5%")
    }

    func testEnglishPluralVariation() throws {
        let en = try bundle(for: "en")
        XCTAssertEqual(String(localized: "\(1) フォルダに適用", bundle: en, locale: Locale(identifier: "en")), "Apply to 1 folder")
        XCTAssertEqual(String(localized: "\(2) フォルダに適用", bundle: en, locale: Locale(identifier: "en")), "Apply to 2 folders")
        let dict = table("Localizable", language: "en")
        let entry = try XCTUnwrap(dict["%lld フォルダに適用"] as? [String: Any])
        XCTAssertNotNil(entry["NSStringLocalizedFormatKey"], "plural entry should live in Localizable.stringsdict")
    }

    func testOtherLanguagesDifferFromJapanese() throws {
        for language in Self.languages where language != "ja" {
            let b = try bundle(for: language)
            XCTAssertNotEqual(b.localizedString(forKey: "履歴", value: nil, table: nil), "履歴", language)
        }
    }

    func testInfoPlistIsLocalized() {
        for language in Self.languages {
            let t = table("InfoPlist", language: language)
            XCTAssertNotNil(t["FolderArt Preset Pack"], language)
        }
    }
}
