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

    /// 全言語で同一であることを許す、固有名詞や記号だけの文言 (訳しようが無いもの)
    private static let identicalEverywhere: Set<String> = [
        "FolderArt", "Avenir Next", "%lld", "%lld / %lld", "%@ · %@", "日本語", "繁體中文", "OK",
    ]
    /// その言語でだけ ja と同一であることを許すキー (簡体字と違って漢字をそのまま使う繁体字など)
    private static let identicalPerLanguage: [String: Set<String>] = [
        "zh-Hant": ["文字", "標準"],
    ]

    /// ja 以外の全言語・全キーについて、値がキー (= 日本語の原文) と違うこと (= 未訳のまま残っていないこと) を見る。
    /// 複数形の variation を持つ辞書エントリは、NSStringLocalizedFormatKey があれば訳済み扱いにして照合をスキップする
    func testOtherLanguagesDifferFromJapanese() throws {
        let ja = table("Localizable", language: "ja")
        var offenders: [(language: String, key: String)] = []
        for language in Self.languages where language != "ja" {
            let other = table("Localizable", language: language)
            let allowed = Self.identicalEverywhere.union(Self.identicalPerLanguage[language] ?? [])
            for key in ja.keys {
                guard !allowed.contains(key), let otherValue = other[key] else { continue }
                if let dict = otherValue as? [String: Any] {
                    if dict["NSStringLocalizedFormatKey"] != nil { continue }   // 複数形は訳済み扱い
                    offenders.append((language, key))
                    continue
                }
                guard let otherString = otherValue as? String, otherString == key else { continue }
                offenders.append((language, key))
            }
        }
        XCTAssertTrue(offenders.isEmpty, offenders.map { "\($0.language): \($0.key)" }.joined(separator: ", "))
    }

    func testInfoPlistIsLocalized() {
        for language in Self.languages {
            let t = table("InfoPlist", language: language)
            XCTAssertNotNil(t["FolderArt Preset Pack"], language)
        }
    }
}
