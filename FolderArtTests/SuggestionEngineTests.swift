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

    // MARK: - 中身からの合流

    private func summary(_ kind: ContentKind, count: Int, representative: RepresentativeImage? = nil) -> ContentSummary {
        ContentSummary(counts: [kind: count], dominant: kind, representative: representative)
    }

    private var sampleImage: RepresentativeImage {
        RepresentativeImage(url: URL(fileURLWithPath: "/tmp/Photos/IMG_001.jpg"),
                            modificationDate: Date(timeIntervalSince1970: 1_700_000_000), thumbnailPNG: Data([1, 2, 3]))
    }

    func testContentFillsOnlyEmptySlots() {
        // 名前で記号・絵文字が埋まっていれば、中身 (画像) では上書きしない
        let s = engine.suggest(for: "music", presets: [], content: summary(.image, count: 5))
        XCTAssertEqual(s.map(\.kind), [.symbol("music.note"), .emoji("🎵")])
    }

    func testContentAloneGivesSymbolAndEmojiWithCount() {
        let s = engine.suggest(for: "xyzzy", presets: [], content: summary(.image, count: 12))
        XCTAssertEqual(s.map(\.kind), [.symbol("photo.fill"), .emoji("📷")])
        XCTAssertTrue(s[0].reason.contains("12"), s[0].reason)
        XCTAssertEqual(s[0].reason, s[1].reason)
    }

    func testFolderDominantGivesNoContentChip() {
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: [], content: summary(.folder, count: 9)).isEmpty)
    }

    func testKindWithoutDictionaryEntryGivesNoContentChip() {
        // このテストの辞書には video の項目が無い
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: [], content: summary(.video, count: 3)).isEmpty)
    }

    func testSymbolMissingFromCatalogSkipsSymbolButKeepsEmoji() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["photo"], symbol: "not.in.catalog", emoji: "📷"),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        let s = localEngine.suggest(for: "xyzzy", presets: [], content: summary(.image, count: 2))
        XCTAssertEqual(s.map(\.kind), [.emoji("📷")])
    }

    func testRepresentativeImageIsAppendedLast() {
        let rep = sampleImage
        let s = engine.suggest(for: "Photos 2024", presets: [], content: summary(.image, count: 5, representative: rep))
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s[3].kind, .image(rep))
        XCTAssertTrue(s[3].reason.contains("IMG_001.jpg"), s[3].reason)
        XCTAssertEqual(s[3].id, "image:/tmp/Photos/IMG_001.jpg:1700000000.0")
    }

    func testImageEqualityIgnoresThumbnailButNotDate() {
        let a = sampleImage
        let b = RepresentativeImage(url: a.url, modificationDate: a.modificationDate, thumbnailPNG: Data([9]))
        let c = RepresentativeImage(url: a.url, modificationDate: a.modificationDate.addingTimeInterval(1), thumbnailPNG: a.thumbnailPNG)
        XCTAssertEqual(Suggestion.Kind.image(a), .image(b))
        XCTAssertNotEqual(Suggestion.Kind.image(a), .image(c))
        XCTAssertNotEqual(Suggestion(kind: .image(a), reason: "").id, Suggestion(kind: .image(c), reason: "").id)
    }

    func testNilContentMatchesLegacyOverload() {
        for name in ["Photos 2024", "xyzzy", "Q3 reports", ""] {
            XCTAssertEqual(engine.suggest(for: name, presets: []), engine.suggest(for: name, presets: [], content: nil), name)
        }
    }

    // MARK: - S1: 誤検出減

    /// 1 書記素の日本語辞書キーは部分一致しない (「動画」の「画」だけでは当たらない)
    func testSingleCharJapaneseKeyDoesNotMatch() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["画"], symbol: "photo.fill", emoji: nil),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        XCTAssertTrue(localEngine.suggest(for: "動画一覧", presets: []).isEmpty)
    }

    /// SF Symbols の曖昧な検索語一致 (names(forTerm:)) は 4 文字以上のトークンのみ。3 文字では経路に入らない
    func testFuzzySymbolSearchRequiresFourChars() {
        let localCatalog = SymbolCatalog(names: ["job.fill"], searchTerms: ["job.fill": ["abc"]])
        let localEngine = SuggestionEngine(dictionary: .empty, catalog: localCatalog)
        XCTAssertTrue(localEngine.suggest(for: "abc", presets: []).isEmpty)
    }

    /// stop-word ("work") 単独では曖昧な SF Symbols 検索に乗らない
    func testStopWordNotFuzzyMatched() {
        let localCatalog = SymbolCatalog(names: ["briefcase.fill"], searchTerms: ["briefcase.fill": ["work"]])
        let localEngine = SuggestionEngine(dictionary: .empty, catalog: localCatalog)
        XCTAssertTrue(localEngine.suggest(for: "work", presets: []).isEmpty)
    }

    // MARK: - S2: ランク改善

    /// 「photo」という語まるごとの一致が、より長い別キー (アルバム整理) の部分一致より symbol 枠を取る
    func testWholeNameMatchRanksFirst() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["photo"], symbol: "photo.fill", emoji: nil),
            SuggestionEntry(keys: ["アルバム整理"], symbol: "star.fill", emoji: nil),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        let s = localEngine.suggest(for: "写真アルバム整理 photo", presets: [])
        XCTAssertEqual(s.first?.kind, .symbol("photo.fill"))
    }

}
