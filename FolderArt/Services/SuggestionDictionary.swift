import Foundation

/// 「語 → 記号名・絵文字」の 1 項目。keys は小文字、日本語は 2 文字以上。
struct SuggestionEntry: Codable, Equatable, Sendable {
    let keys: [String]
    let symbol: String?
    let emoji: String?
}

/// 同梱の suggestions.json。読めなければ空 (提案は規則と検索語だけで動く)。
struct SuggestionDictionary: Equatable {
    let entries: [SuggestionEntry]

    static let empty = SuggestionDictionary(entries: [])

    init(entries: [SuggestionEntry]) {
        self.entries = entries
    }

    static func load(bundle: Bundle = .main, resourceName: String = "suggestions") -> SuggestionDictionary {
        for b in [bundle, Bundle.main] {
            if let url = b.url(forResource: resourceName, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let entries = try? JSONDecoder().decode([SuggestionEntry].self, from: data) {
                return SuggestionDictionary(entries: entries)
            }
        }
        return .empty
    }

    /// 代表キー (小文字) を持つ項目。中身からの提案が種類 → 記号・絵文字を引くのに使う
    func entry(forKey key: String) -> SuggestionEntry? {
        entries.first { $0.keys.contains(key) }
    }
}

/// ユーザー辞書 (suggestions-user.json) の読み込みで起きる失敗。文言はアラート「提案辞書を読めません: …」の後ろに付く
enum UserDictionaryError: LocalizedError, Equatable {
    case tooLarge(Int)
    case tooManyEntries(Int)
    case tooManyKeys(Int)
    case keyTooLong(String)
    case symbolTooLong(String)
    case emojiTooLong(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return String(localized: "提案辞書のファイルが大きすぎます (上限 \(SuggestionDictionary.userMaxFileBytes / 1024 / 1024) MB)")
        case .tooManyEntries(let n):
            return String(localized: "提案辞書の項目が多すぎます (\(n) 件、上限 \(SuggestionDictionary.userMaxEntries) 件)")
        case .tooManyKeys(let n):
            return String(localized: "提案辞書の 1 項目のキーが多すぎます (\(n) 個、上限 \(SuggestionDictionary.userMaxKeysPerEntry) 個)")
        case .keyTooLong(let key):
            return String(localized: "提案辞書のキーが長すぎます: \(key)")
        case .symbolTooLong(let symbol):
            return String(localized: "提案辞書の記号名が長すぎます: \(symbol)")
        case .emojiTooLong(let emoji):
            return String(localized: "提案辞書の絵文字が長すぎます: \(emoji)")
        case .malformed(let reason):
            return String(localized: "提案辞書の JSON の形式が違います: \(reason)")
        }
    }
}

extension SuggestionDictionary {
    static let userFileName = "suggestions-user.json"
    static let userMaxFileBytes = 1 * 1024 * 1024
    static let userMaxEntries = 1000
    static let userMaxKeysPerEntry = 50
    static let userMaxKeyLength = 64
    static let userMaxSymbolLength = 100
    static let userMaxEmojiLength = 8

    /// 「提案辞書を開く…」がファイルを作るときの雛形 (例を 1 件)。
    /// 2 つ目のキーは Unicode エスケープで書く (build-xcstrings.py --check は複数行文字列の中の
    /// 日本語もソース文言として拾ってしまうため。実行時の値は "サンプル" と同じ)
    static let userTemplate = """
    [
      {"keys": ["example", "\u{30B5}\u{30F3}\u{30D7}\u{30EB}"], "symbol": "star.fill", "emoji": "⭐"}
    ]

    """

    /// ユーザー辞書を読む。無ければ nil、読めない・形式が違う・上限超えなら .failure。
    /// 成功側は正規化と整理 (normalizedUser) を済ませてある。メインの外から呼んでよい (ファイル I/O)
    static func loadUser(at url: URL) -> Result<SuggestionDictionary, Error>? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            // 復号の前にサイズで弾く (巨大なファイルを丸ごとメモリに載せない)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int, size > userMaxFileBytes { throw UserDictionaryError.tooLarge(size) }
            let data = try Data(contentsOf: url)
            guard data.count <= userMaxFileBytes else { throw UserDictionaryError.tooLarge(data.count) }
            let raw: [SuggestionEntry]
            do {
                raw = try JSONDecoder().decode([SuggestionEntry].self, from: data)
            } catch {
                throw UserDictionaryError.malformed(error.localizedDescription)
            }
            return .success(try normalizedUser(raw))
        } catch {
            return .failure(error)
        }
    }

    /// ユーザー辞書の項目を整える。順に:
    /// 1. キーを NFKC + 小文字化し前後の空白を落とす。空になったキーは捨てる。項目内の重複は 1 つにまとめる
    /// 2. 項目間で同じキーは先の項目が勝ち、後の項目から外す
    /// 3. symbol / emoji の空文字は nil 扱い。両方 nil の項目は捨てる
    /// 4. キーが無くなった項目は捨てる
    /// 上限 (ファイルサイズは loadUser で、項目数・キー数・長さはここで) を超えれば throw する。
    /// 日本語キーの「2 文字以上」の規則はユーザー辞書には課さない
    static func normalizedUser(_ raw: [SuggestionEntry]) throws -> SuggestionDictionary {
        guard raw.count <= userMaxEntries else { throw UserDictionaryError.tooManyEntries(raw.count) }
        var seen = Set<String>()
        var entries: [SuggestionEntry] = []
        for entry in raw {
            guard entry.keys.count <= userMaxKeysPerEntry else { throw UserDictionaryError.tooManyKeys(entry.keys.count) }
            var keys: [String] = []
            for rawKey in entry.keys {
                let key = rawKey.precomposedStringWithCompatibilityMapping.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                guard PackReader.withinLimit(key, graphemes: userMaxKeyLength) else {
                    throw UserDictionaryError.keyTooLong(String(key.prefix(userMaxKeyLength)))
                }
                guard !keys.contains(key), !seen.contains(key) else { continue }
                keys.append(key)
            }
            let symbol = entry.symbol.flatMap { $0.isEmpty ? nil : $0 }
            let emoji = entry.emoji.flatMap { $0.isEmpty ? nil : $0 }
            if let symbol, !PackReader.withinLimit(symbol, graphemes: userMaxSymbolLength) {
                throw UserDictionaryError.symbolTooLong(String(symbol.prefix(userMaxSymbolLength)))
            }
            if let emoji, !PackReader.withinLimit(emoji, graphemes: userMaxEmojiLength) {
                throw UserDictionaryError.emojiTooLong(String(emoji.prefix(userMaxEmojiLength)))
            }
            guard !keys.isEmpty, symbol != nil || emoji != nil else { continue }
            seen.formUnion(keys)
            entries.append(SuggestionEntry(keys: keys, symbol: symbol, emoji: emoji))
        }
        return SuggestionDictionary(entries: entries)
    }

    /// ユーザー辞書の項目を先頭に置き、同じキーを持つ同梱項目からはそのキーを外す。キーが無くなった同梱項目は捨てる。
    /// user は normalizedUser 済み (キーの重複が無い) であること
    static func merging(user: SuggestionDictionary, bundled: SuggestionDictionary) -> SuggestionDictionary {
        let userKeys = Set(user.entries.flatMap(\.keys))
        var entries = user.entries
        for entry in bundled.entries {
            let keys = entry.keys.filter { !userKeys.contains($0) }
            guard !keys.isEmpty else { continue }
            entries.append(SuggestionEntry(keys: keys, symbol: entry.symbol, emoji: entry.emoji))
        }
        return SuggestionDictionary(entries: entries)
    }
}
