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

    // MARK: - S4: 提案辞書の他言語キー

    /// 同梱辞書のドイツ語キー ("rechnungen") がフォルダ名まるごと一致で 請求書/invoice の項目を引く
    func testGermanKeyMatchesBundledInvoiceEntry() {
        let bundled = SuggestionDictionary.load(bundle: Bundle(for: SuggestionEngineTests.self))
        let bundledCatalog = SymbolCatalog(names: ["doc.text.fill"], searchTerms: [:])
        let bundledEngine = SuggestionEngine(dictionary: bundled, catalog: bundledCatalog)
        let s = bundledEngine.suggest(for: "Rechnungen", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("doc.text.fill"), .emoji("🧾")])
    }

    /// 同梱辞書の繁體中文キー ("音樂") が 音楽/music の項目を引く (2 文字以上の部分一致)
    func testTraditionalChineseKeyMatchesBundledMusicEntry() {
        let bundled = SuggestionDictionary.load(bundle: Bundle(for: SuggestionEngineTests.self))
        let bundledCatalog = SymbolCatalog(names: ["music.note"], searchTerms: [:])
        let bundledEngine = SuggestionEngine(dictionary: bundled, catalog: bundledCatalog)
        let s = bundledEngine.suggest(for: "音樂", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("music.note"), .emoji("🎵")])
    }

    // MARK: - Codex P2: 非 Latin も境界でまるごと一致を認識する

    /// 「写真 2026」では区切られた「写真」がまるごと一致として、埋め込みの長い部分一致 (別項目) より symbol 枠を取る
    func testNonLatinWholeTokenOutranksLongerEmbeddedPartial() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["写真"], symbol: "photo.fill", emoji: nil),
            // 実運用にはない語だが、「写真」の前後の空白をまたいで埋め込みで一致する長いキーを人工的に作り、
            // 「まるごと一致でない部分一致」が「区切られたまるごと一致」に競り勝ってしまう不具合を再現する
            SuggestionEntry(keys: ["真 20"], symbol: "star.fill", emoji: nil),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        let s = localEngine.suggest(for: "写真 2026", presets: [])
        XCTAssertEqual(s.first?.kind, .symbol("photo.fill"))
    }

    /// 「資料 2026」は区切られたまるごと一致なので、stop-word でも資料/material の項目が出る
    func testStopWordWholeTokenStillMatchesInDictionary() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["資料"], symbol: "books.vertical.fill", emoji: "📚"),
        ])
        let localCatalog = SymbolCatalog(names: ["books.vertical.fill"], searchTerms: [:])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: localCatalog)
        let s = localEngine.suggest(for: "資料 2026", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("books.vertical.fill"), .emoji("📚"), .text("2026")])
    }

    /// 「旅行資料」のように区切りなく埋め込まれた stop-word キーは、まるごと一致でないので従来どおり出ない
    func testStopWordEmbeddedPartialStillSuppressedInDictionary() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["資料"], symbol: "books.vertical.fill", emoji: "📚"),
        ])
        let localCatalog = SymbolCatalog(names: ["books.vertical.fill"], searchTerms: [:])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: localCatalog)
        XCTAssertTrue(localEngine.suggest(for: "旅行資料", presets: []).isEmpty)
    }

    // MARK: - Codex P2 (2巡目): ユーザー辞書の 1 文字キーはまるごと一致なら活きる

    private func writeUserDict(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SuggestionEngineTests_\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    /// SuggestionDictionary.normalizedUser は同梱辞書と違い日本語キーの「2 文字以上」規則を課さない。
    /// フォルダ名がまるごとそのキーなら、ユーザーが定義した 1 文字キー ("猫") も活きる
    func testUserDictionarySingleCharKeyWholeMatchFires() throws {
        let url = try writeUserDict(#"[{"keys": ["猫"], "emoji": "🐱"}]"#)
        guard case .success(let userDict)? = SuggestionDictionary.loadUser(at: url) else {
            return XCTFail("ユーザー辞書の読み込みに失敗した")
        }
        let localEngine = SuggestionEngine(dictionary: userDict, catalog: catalog)
        let s = localEngine.suggest(for: "猫", presets: [])
        XCTAssertEqual(s.map(\.kind), [.emoji("🐱")])
    }

    /// 同じ 1 文字キーでも、区切りなく埋め込まれた部分一致 ("子猫") では誤爆を避けるため出さない
    func testUserDictionarySingleCharKeyEmbeddedPartialSuppressed() throws {
        let url = try writeUserDict(#"[{"keys": ["猫"], "emoji": "🐱"}]"#)
        guard case .success(let userDict)? = SuggestionDictionary.loadUser(at: url) else {
            return XCTFail("ユーザー辞書の読み込みに失敗した")
        }
        let localEngine = SuggestionEngine(dictionary: userDict, catalog: catalog)
        XCTAssertTrue(localEngine.suggest(for: "子猫", presets: []).isEmpty)
    }

    // MARK: - Codex P2 (3巡目): 項目内のキー選択もまるごと一致を優先する

    /// 項目内に「写真」(まるごと) と「旅行写真」(「旅行写真集」に埋め込みの部分一致) の両方が一致する場合、
    /// 最長というだけで「旅行写真」を採用すると項目全体がまるごと一致扱いされなくなり、
    /// 別項目 (資料、まるごと一致) に symbol 枠を奪われてしまう。「写真」を採用してまるごと一致を保つべき
    func testEntryPicksWholeTokenKeyOverLongerEmbeddedPartial() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["写真", "旅行写真"], symbol: "photo.fill", emoji: nil),
            SuggestionEntry(keys: ["資料"], symbol: "books.vertical.fill", emoji: nil),
        ])
        let localCatalog = SymbolCatalog(names: ["photo.fill", "books.vertical.fill"], searchTerms: [:])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: localCatalog)
        let s = localEngine.suggest(for: "写真 旅行写真集 資料", presets: [])
        XCTAssertEqual(s.first?.kind, .symbol("photo.fill"))
    }

    // MARK: - PR-3: アクセント付き Latin キーはトークン一致のみ (部分一致で誤爆しない)

    /// アクセント付き Latin キー ("météo") は、区切られたまるごと一致では引くが、
    /// 別語の一部 ("météorites") には substring では当たらない。
    /// 同梱辞書の weather 項目は keys に "météo" を含む (cloud.sun.fill / 🌤️)
    func testAccentedLatinKeyMatchesWholeTokenNotEmbedded() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["météo"], symbol: "cloud.sun.fill", emoji: "🌤️"),
        ])
        let localCatalog = SymbolCatalog(names: ["cloud.sun.fill"], searchTerms: [:])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: localCatalog)
        // まるごと一致: 天気の提案 (記号・絵文字) が出る
        // (accented 語は latinTokens で断片化し第4層が短コード text を足しうるので、weather 項目の有無で判定する)
        let whole = localEngine.suggest(for: "Photos météo", presets: []).map(\.kind)
        XCTAssertTrue(whole.contains(.symbol("cloud.sun.fill")), "\(whole)")
        XCTAssertTrue(whole.contains(.emoji("🌤️")), "\(whole)")
        // 別語の一部 (隕石): weather 項目は substring では当たらない (再設計前は誤爆していた)
        let embedded = localEngine.suggest(for: "météorites", presets: []).map(\.kind)
        XCTAssertFalse(embedded.contains(.symbol("cloud.sun.fill")), "\(embedded)")
        XCTAssertFalse(embedded.contains(.emoji("🌤️")), "\(embedded)")
    }

    /// ASCII キー ("photo") も区切られたまるごと一致のみで、より長い別語 ("photography") には当たらない
    func testASCIIKeyMatchesWholeTokenNotLongerWord() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["photo"], symbol: "photo.fill", emoji: "📷"),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        XCTAssertEqual(localEngine.suggest(for: "photo 2026", presets: []).first?.kind, .symbol("photo.fill"))
        XCTAssertTrue(localEngine.suggest(for: "photography", presets: []).isEmpty)
    }

    // MARK: - PR-2: まるごと一致の位置は「区切られた出現」で測る

    /// 先に埋め込み出現 (旅行写真集 の 写真、index 2) があり、後ろに区切られたまるごと出現 (末尾の 写真) がある場合、
    /// まるごと一致の位置を末尾の出現で測るべき。埋め込み位置 (2) で測ると、
    /// 同じくまるごと一致の 資料 (index 5) より不当に「先」扱いされ symbol 枠を奪ってしまう。
    /// 資料 (先に区切られて出る) が 写真 (後ろで区切られて出る) より先に来ること
    func testWholeTokenPositionUsesQualifyingOccurrence() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["写真"], symbol: "photo.fill", emoji: "📷"),
            SuggestionEntry(keys: ["資料"], symbol: "books.vertical.fill", emoji: "📚"),
        ])
        let localCatalog = SymbolCatalog(names: ["photo.fill", "books.vertical.fill"], searchTerms: [:])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: localCatalog)
        let s = localEngine.suggest(for: "旅行写真集 資料 写真", presets: [])
        XCTAssertEqual(s.first?.kind, .symbol("books.vertical.fill"))
    }

    // MARK: - Codex PR-4: 自己重複するキーの重なった出現でのまるごと一致

    /// 自己重複するキー "a-a" は、フォルダ名 "xa-a-a" では先頭の埋め込み出現 (前が 'x' で境界でない) の後、
    /// それに重なる末尾の位置でだけ区切られたまるごと 1 語になる。重複走査を upperBound へ飛ばすと
    /// この重なった出現を取りこぼし、"a-a" はハイフン込みで全 Latin (=部分一致不可) なので提案が完全に消える。
    /// index(after: lowerBound) で 1 文字ずつ進めれば重なった出現も拾える (再設計前は空だった → RED)。
    func testSelfOverlappingKeyWholeMatchAtOverlappingOccurrence() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["a-a"], symbol: nil, emoji: "🅰️"),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        // "xa" が第4層の短コード規則で .text("XA") を副次的に足しうるので、辞書の emoji の有無で判定する
        let s = localEngine.suggest(for: "xa-a-a", presets: []).map(\.kind)
        XCTAssertTrue(s.contains(.emoji("🅰️")), "\(s)")
    }

}
