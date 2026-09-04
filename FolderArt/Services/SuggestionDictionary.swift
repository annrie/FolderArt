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
}
