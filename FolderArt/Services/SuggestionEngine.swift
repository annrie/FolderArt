import Foundation

/// フォルダ名から候補を作る純関数。優先順: お気に入り → 辞書 → SF Symbols の検索語 → 規則。
struct SuggestionEngine {
    let dictionary: SuggestionDictionary
    let catalog: SymbolCatalog

    /// 誤検出しやすい一般語。曖昧な SF Symbols 検索 (第3層) と、辞書の非 Latin 部分一致
    /// (まるごと一致でないもの) では候補にしない。辞書に明示キーとして入っている語には効かせない
    static let stopWords: Set<String> = [
        "new", "old", "my", "the", "and", "for", "temp", "tmp", "misc", "other",
        "data", "file", "files", "folder", "backup", "download", "downloads",
        "work", "test", "project", "その他", "新規", "一時", "資料",  // loc-ignore
    ]

    init(dictionary: SuggestionDictionary, catalog: SymbolCatalog) {
        self.dictionary = dictionary
        self.catalog = catalog
    }

    func suggest(for folderName: String, presets: [Preset]) -> [Suggestion] {
        suggest(for: folderName, presets: presets, content: nil)
    }

    /// 名前からの候補 (記号・絵文字・文字) を先に作り、中身の多数派で空いた枠だけ埋め、代表画像があれば末尾に足す。最大 4
    func suggest(for folderName: String, presets: [Preset], content: ContentSummary?) -> [Suggestion] {
        var (symbol, emoji, text) = nameSuggestions(for: folderName, presets: presets)

        if let content, let kind = content.dominant, let key = kind.dictionaryKey,
           let count = content.counts[kind], let reason = kind.reason(count: count) {
            let entry = dictionary.entry(forKey: key)
            if symbol == nil, let name = entry?.symbol, catalog.contains(name) {
                symbol = Suggestion(kind: .symbol(name), reason: reason)
            }
            if emoji == nil, let e = entry?.emoji {
                emoji = Suggestion(kind: .emoji(e), reason: reason)
            }
        }

        var out = [symbol, emoji, text].compactMap { $0 }
        if let rep = content?.representative {
            out.append(Suggestion(kind: .image(rep), reason: String(localized: "中身の画像「\(rep.url.lastPathComponent)」")))
        }
        return out
    }

    /// 第2段階の 4 層 (お気に入り → 辞書 → 検索語 → 規則)。枠ごとの候補を返す
    private func nameSuggestions(for folderName: String, presets: [Preset]) -> (symbol: Suggestion?, emoji: Suggestion?, text: Suggestion?) {
        let normalized = Self.normalize(folderName)
        guard !normalized.isEmpty else { return (nil, nil, nil) }
        let tokens = Self.latinTokens(normalized)

        var symbol: Suggestion?
        var emoji: Suggestion?
        var text: Suggestion?

        // 1. お気に入り (名前がフォルダ名に含まれる) は記号枠で最優先
        for preset in presets {
            let key = Self.normalize(preset.name)
            // 1 文字の英数字名は誤爆しやすいので除くが、絵文字などの 1 文字は通す (お気に入りの既定名は絵文字そのもの)
            let isShortASCII = key.count < 2 && key.unicodeScalars.allSatisfy(\.isASCII)
            guard !key.isEmpty, !isShortASCII, normalized.contains(key) else { continue }
            symbol = Suggestion(kind: .preset(preset), reason: String(localized: "お気に入り「\(preset.name)」"))
            break
        }

        // 2. 辞書: 項目ごとに一致したキーのうち最長のもの (同じ長さなら先に出た方) を採用し、
        //    項目間は「キーの長い順、同じ長さならフォルダ名の先に出た順」に並べる。
        //    (sort の安定性には頼らず、位置によるタイブレークで並び順を明示的に決定的にする)
        func position(of key: String) -> Int {
            normalized.range(of: key).map { normalized.distance(from: normalized.startIndex, to: $0.lowerBound) } ?? Int.max
        }
        // key が区切られたまるごと 1 語なら true。isWholeToken は key == normalized も
        // 区切り出現も両方カバーするので、旧 (k == normalized || tokens.contains(...)) は不要。
        func isWhole(_ key: String) -> Bool {
            Self.isWholeToken(key, in: normalized)
        }
        // key が区切られたまるごと 1 語として最初に現れる位置 (無ければ nil)。
        // ランキングのタイブレークで、埋め込み出現ではなくまるごと一致の位置を使うため。
        func firstWholeTokenPosition(of key: String) -> Int? {
            Self.firstWholeTokenIndex(of: key, in: normalized)
                .map { normalized.distance(from: normalized.startIndex, to: $0) }
        }
        var hits: [(key: String, position: Int, entry: SuggestionEntry, isWholeMatch: Bool)] = []
        for entry in dictionary.entries {
            let matching = entry.keys.filter { key in
                guard normalized.contains(key) else { return false }
                // 区切られたまるごと 1 語は、どの字種でも・長さや stop-word を問わず通す
                // (ユーザー辞書の 1 文字キー "猫"/"★"、アクセント付き Latin のまるごと一致も活きる)。
                if Self.isWholeToken(key, in: normalized) { return true }
                // 埋め込み部分一致は、語の区切り (空白) を持たない字種 (漢字・かな・ハングル) のキーだけ許す。
                // Latin (ASCII/アクセント付き) は substring だと誤爆するのでトークン一致のみにする
                // (météo が météorites に当たる、を防ぐ)。1 書記素キーと stop-word も除く。
                return Self.needsSubstringMatch(key) && key.count >= 2 && !Self.stopWords.contains(key)
            }
            // まるごと一致のキーを、長いだけの埋め込み部分一致より優先して採用する
            // (そうしないと項目全体がまるごと一致扱いされなくなる)
            if let best = matching.max(by: {
                (isWhole($0) ? 1 : 0, $0.count, -position(of: $0)) < (isWhole($1) ? 1 : 0, $1.count, -position(of: $1))
            }) {
                // まるごと一致なら、埋め込み出現ではなくまるごと一致の位置で並べる
                // (先に埋め込み出現がある語が、後ろのまるごと出現なのに不当に「先」扱いされないように)
                let whole = isWhole(best)
                let pos = whole ? (firstWholeTokenPosition(of: best) ?? position(of: best)) : position(of: best)
                hits.append((best, pos, entry, whole))
            }
        }
        // まるごと一致 → キーが長い → フォルダ名の先に出た順、の優先度で並べる
        hits.sort {
            let l = ($0.isWholeMatch ? 1 : 0, $0.key.count, -$0.position)
            let r = ($1.isWholeMatch ? 1 : 0, $1.key.count, -$1.position)
            return l > r
        }
        for hit in hits {
            if symbol == nil, let name = hit.entry.symbol, catalog.contains(name) {
                symbol = Suggestion(kind: .symbol(name), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if emoji == nil, let e = hit.entry.emoji {
                emoji = Suggestion(kind: .emoji(e), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if symbol != nil && emoji != nil { break }
        }

        // 3. SF Symbols の検索語 (辞書に無い英単語)。曖昧な検索語一致は 4 文字以上・stop-word 以外のみ
        if symbol == nil {
            for token in tokens where token.count >= 3 {
                if catalog.contains(token) {
                    symbol = Suggestion(kind: .symbol(token), reason: String(localized: "記号名「\(token)」"))
                    break
                }
                if token.count >= 4, !Self.stopWords.contains(token), let name = catalog.names(forTerm: token).first {
                    symbol = Suggestion(kind: .symbol(name), reason: String(localized: "検索語「\(token)」に一致"))
                    break
                }
            }
        }

        // 4. 規則: 4 桁の数字、2 文字以内の英数字 → 文字
        for token in tokens {
            if Self.isYear(token) || Self.isShortCode(token) {
                let value = Self.isShortCode(token) ? token.uppercased() : token
                text = Suggestion(kind: .text(value), reason: String(localized: "フォルダ名の「\(value)」"))
                break
            }
        }

        return (symbol, emoji, text)
    }

    // MARK: - 正規化と分割

    /// NFKC (全角英数字 → 半角、半角カナ → 全角カナ) + 小文字。
    /// camelCase の境界には小文字化の前に空白を挿入する:
    /// 小文字/数字 → 大文字 (myPhoto → my Photo) と、頭字語の末尾 (大文字 → 大文字 + 小文字: PDFDocs → PDF Docs)
    static func normalize(_ s: String) -> String {
        let chars = Array(s)
        var spaced = ""
        for (i, ch) in chars.enumerated() {
            if i > 0, ch.isUppercase {
                let previous = chars[i - 1]
                let nextIsLower = i + 1 < chars.count && chars[i + 1].isLowercase
                if previous.isLowercase || previous.isNumber || (previous.isUppercase && nextIsLower) { spaced.append(" ") }
            }
            spaced.append(ch)
        }
        return spaced.precomposedStringWithCompatibilityMapping.lowercased()
    }

    /// 空白・記号で切った英数字の語 (小文字)。日本語などはトークンにしない (辞書は部分文字列で当てる)。
    static func latinTokens(_ normalized: String) -> [String] {
        var out: [String] = []
        var current = ""
        for ch in normalized {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                current.append(ch)
            } else {
                // 空白・記号・日本語などは区切り (日本語はトークンにしない)
                if !current.isEmpty { out.append(current); current = "" }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    /// key がフォルダ名の中で「まるごと 1 語」として現れるか (前後が文字列端か英数字以外=空白/句読点)。
    /// 非 Latin (日本語・中国語など) は latinTokens で語に割れないので、境界で判定する。
    static func isWholeToken(_ key: String, in text: String) -> Bool {
        firstWholeTokenIndex(of: key, in: text) != nil
    }

    /// key が text 内で「まるごと 1 語」(前後が文字列端か英数字以外) として最初に現れる範囲の下限位置。無ければ nil。
    /// isWholeToken とランキングのタイブレーク (firstWholeTokenPosition) で境界走査を共有する。
    static func firstWholeTokenIndex(of key: String, in text: String) -> String.Index? {
        guard !key.isEmpty else { return nil }
        var searchStart = text.startIndex
        while let r = text.range(of: key, range: searchStart..<text.endIndex) {
            let beforeOK = r.lowerBound == text.startIndex || {
                let c = text[text.index(before: r.lowerBound)]; return !(c.isLetter || c.isNumber)
            }()
            let afterOK = r.upperBound == text.endIndex || {
                let c = text[r.upperBound]; return !(c.isLetter || c.isNumber)
            }()
            if beforeOK && afterOK { return r.lowerBound }
            // 1 文字だけ進めて次の出現を探す (旅行写真 は写真の前が letter で false、他所に境界出現があれば拾う)。
            // upperBound へ飛ぶと、自己重複するキー ("a-a" が "xa-a-a" の重なった位置でだけまるごと一致する等)
            // の重なった出現を取りこぼす。lowerBound < endIndex なので index(after:) は安全、必ず 1 文字進むので停止する。
            searchStart = text.index(after: r.lowerBound)
        }
        return nil
    }

    /// 語の区切り (空白) を持たない字種 (漢字・かな・ハングル) をキーが含むか。
    /// これらだけ埋め込み部分一致を許し、Latin (アクセント付き含む) はトークン一致のみにする。
    static func needsSubstringMatch(_ key: String) -> Bool {
        key.unicodeScalars.contains { s in
            (0x3040...0x30FF).contains(s.value) ||   // Hiragana + Katakana
            (0x31F0...0x31FF).contains(s.value) ||   // Katakana phonetic ext
            (0x3400...0x4DBF).contains(s.value) ||   // CJK Ext A
            (0x4E00...0x9FFF).contains(s.value) ||   // CJK Unified
            (0xF900...0xFAFF).contains(s.value) ||   // CJK Compatibility
            (0xAC00...0xD7A3).contains(s.value) ||   // Hangul syllables
            (0x1100...0x11FF).contains(s.value) ||   // Hangul Jamo
            (0x3130...0x318F).contains(s.value)      // Hangul compatibility Jamo
        }
    }

    static func isYear(_ token: String) -> Bool {
        token.count == 4 && token.allSatisfy(\.isNumber)
    }

    static func isShortCode(_ token: String) -> Bool {
        (1...2).contains(token.count) && token.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
