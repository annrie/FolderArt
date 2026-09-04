import Foundation

/// フォルダ名から候補を作る純関数。優先順: お気に入り → 辞書 → SF Symbols の検索語 → 規則。
struct SuggestionEngine {
    let dictionary: SuggestionDictionary
    let catalog: SymbolCatalog

    init(dictionary: SuggestionDictionary, catalog: SymbolCatalog) {
        self.dictionary = dictionary
        self.catalog = catalog
    }

    func suggest(for folderName: String, presets: [Preset]) -> [Suggestion] {
        let normalized = Self.normalize(folderName)
        guard !normalized.isEmpty else { return [] }
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
        var hits: [(key: String, position: Int, entry: SuggestionEntry)] = []
        for entry in dictionary.entries {
            let matching = entry.keys.filter { key in
                let isLatin = key.unicodeScalars.allSatisfy { $0.isASCII }
                return isLatin ? tokens.contains(key) : normalized.contains(key)
            }
            if let best = matching.max(by: { ($0.count, -position(of: $0)) < ($1.count, -position(of: $1)) }) {
                hits.append((best, position(of: best), entry))
            }
        }
        hits.sort { ($0.key.count, -$0.position) > ($1.key.count, -$1.position) }
        for hit in hits {
            if symbol == nil, let name = hit.entry.symbol, catalog.contains(name) {
                symbol = Suggestion(kind: .symbol(name), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if emoji == nil, let e = hit.entry.emoji {
                emoji = Suggestion(kind: .emoji(e), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if symbol != nil && emoji != nil { break }
        }

        // 3. SF Symbols の検索語 (辞書に無い英単語)
        if symbol == nil {
            for token in tokens where token.count >= 3 {
                if catalog.contains(token) {
                    symbol = Suggestion(kind: .symbol(token), reason: String(localized: "記号名「\(token)」"))
                    break
                }
                if let name = catalog.names(forTerm: token).first {
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

        return [symbol, emoji, text].compactMap { $0 }
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

    static func isYear(_ token: String) -> Bool {
        token.count == 4 && token.allSatisfy(\.isNumber)
    }

    static func isShortCode(_ token: String) -> Bool {
        (1...2).contains(token.count) && token.allSatisfy { $0.isLetter || $0.isNumber }
    }
}
