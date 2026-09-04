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

    func testLongestMatchingKeyWinsWithinEntry() {
        // 項目内に短いキーと長いキーの両方が一致する場合、最長のキーを採用する (reason にも反映される)
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["請求", "請求書"], symbol: "doc.text.fill", emoji: "🧾"),
            SuggestionEntry(keys: ["控え"], symbol: "star.fill", emoji: "⭐"),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        let s = localEngine.suggest(for: "2025年 請求書 控え", presets: [])
        XCTAssertEqual(s.first?.kind, .symbol("doc.text.fill"))
        XCTAssertTrue(s.first?.reason.contains("請求書") ?? false)
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

    func testCamelCaseAcronymBoundary() {
        XCTAssertEqual(SuggestionEngine.normalize("myPDFDocs"), "my pdf docs")
        XCTAssertEqual(SuggestionEngine.normalize("PDF"), "pdf")
        XCTAssertEqual(SuggestionEngine.normalize("MyPhoto2024"), "my photo2024")
        XCTAssertEqual(SuggestionEngine.latinTokens(SuggestionEngine.normalize("myPDFDocs")), ["my", "pdf", "docs"])
    }

    /// お気に入りの既定名は絵文字そのものなので、1 文字でも絵文字なら提案する (1 文字の英数字は誤爆しやすいので除く)
    func testOneGraphemeEmojiFavoriteIsSuggested() {
        let plane = Preset(name: "✈️", overlay: .emoji("✈️"), settings: CompositionSettings())
        let s = engine.suggest(for: "旅行 ✈️", presets: [plane])
        XCTAssertEqual(s.first?.kind, .preset(plane))
        let a = Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())
        XCTAssertFalse(engine.suggest(for: "Photos", presets: [a]).contains { $0.kind == .preset(a) })
    }

}
