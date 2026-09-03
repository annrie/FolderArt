import XCTest
@testable import FolderArt

final class SuggestionEngineTests: XCTestCase {

    private let dict = SuggestionDictionary(entries: [
        SuggestionEntry(keys: ["写真", "photo", "photos"], symbol: "photo.fill", emoji: "📷"),
        SuggestionEntry(keys: ["請求書", "invoice"], symbol: "doc.text.fill", emoji: "🧾"),
        SuggestionEntry(keys: ["音楽", "music"], symbol: "music.note", emoji: "🎵"),
        SuggestionEntry(keys: ["設定", "config"], symbol: "gearshape.fill", emoji: nil),
    ])
    private let catalog = SymbolCatalog(
        names: ["photo.fill", "doc.text.fill", "music.note", "gearshape.fill", "figure.run", "star.fill"],
        searchTerms: ["figure.run": ["running", "sports"], "star.fill": ["favorite"]])
    private var engine: SuggestionEngine { SuggestionEngine(dictionary: dict, catalog: catalog) }

    func testNormalizeFoldsWidthAndCase() {
        XCTAssertEqual(SuggestionEngine.normalize("Ｐｈｏｔｏ　２０２５"), "photo 2025")
        XCTAssertEqual(SuggestionEngine.latinTokens("photo_2025-final.v2 (draft)"), ["photo", "2025", "final", "v2", "draft"])
        XCTAssertEqual(SuggestionEngine.latinTokens(SuggestionEngine.normalize("myPhotoAlbum")), ["my", "photo", "album"])
    }

    func testEnglishWordHitsDictionary() {
        let s = engine.suggest(for: "Photos 2024", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("photo.fill"), .emoji("📷"), .text("2024")])
    }

    func testJapaneseSubstringHitsDictionaryLongestFirst() {
        let s = engine.suggest(for: "2025年 請求書 控え", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("doc.text.fill"), .emoji("🧾"), .text("2025")])
    }

    func testJapaneseKeyDoesNotMatchInsideUnrelatedWord() {
        // 「設定」は含まれない。「定」だけ、「設」だけの語には当たらない
        let s = engine.suggest(for: "予定表", presets: [])
        XCTAssertTrue(s.isEmpty)
    }

    func testFavoriteWinsTheSymbolSlot() {
        let preset = Preset(name: "photo", overlay: .text("P"), settings: CompositionSettings())
        let s = engine.suggest(for: "photo backup", presets: [preset])
        XCTAssertEqual(s.first?.kind, .preset(preset))
        XCTAssertEqual(s.count, 2)                       // お気に入り + 絵文字 (辞書)、記号枠は使われ済み
        XCTAssertEqual(s[1].kind, .emoji("📷"))
    }

    func testSearchTermFallbackWhenDictionaryMisses() {
        let s = engine.suggest(for: "Sports club", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("figure.run")])
    }

    func testRulesProduceTextForYearsAndShortCodes() {
        XCTAssertEqual(engine.suggest(for: "2026", presets: []).map(\.kind), [.text("2026")])
        XCTAssertEqual(engine.suggest(for: "Q3 reports", presets: []).map(\.kind), [.text("Q3")])
        XCTAssertTrue(engine.suggest(for: "12345", presets: []).isEmpty)   // 5 桁は対象外
    }

    func testAtMostThreeAndNoDuplicateKinds() {
        // 辞書で記号+絵文字、規則で文字。合計 3 を超えない
        let s = engine.suggest(for: "music photo 2024 A", presets: [])
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].kind, .symbol("music.note"))   // 最初に当たった語の記号
        XCTAssertEqual(s[1].kind, .emoji("🎵"))
        XCTAssertEqual(s[2].kind, .text("2024"))
    }

    func testEmptyWhenNothingMatches() {
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: []).isEmpty)
        XCTAssertTrue(engine.suggest(for: "", presets: []).isEmpty)
    }

    func testIdsAreStable() {
        let a = engine.suggest(for: "photo", presets: [])
        let b = engine.suggest(for: "photo", presets: [])
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.first?.id, "symbol:photo.fill")
    }
}
