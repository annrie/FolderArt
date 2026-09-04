import Foundation

/// 実行中の macOS が持つ SF Symbols のカタログ。制限付き記号 (Apple 製品・機能を表すもの) は除外する。
struct SymbolCatalog {
    let names: [String]
    let searchTerms: [String: [String]]   // テストから memberwise init で注入できるよう internal
    let nameSet: Set<String>              // names の高速検索用。別ファイルの extension からは private が見えないため internal

    init(names: [String], searchTerms: [String: [String]]) {
        self.names = names
        self.searchTerms = searchTerms
        self.nameSet = Set(names)
    }

    /// 画面で使う共有インスタンス。読み込みは数千件の plist を舐めるので 1 回だけにする
    static let shared = SymbolCatalog.load()

    static let coreGlyphsResources = URL(fileURLWithPath:
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// 検索語が空のときに先頭に出す定番
    static let popularNames: [String] = [
        "star.fill", "heart.fill", "folder.fill", "doc.fill", "photo.fill", "camera.fill",
        "music.note", "film.fill", "book.fill", "pencil", "paintbrush.fill", "hammer.fill",
        "wrench.fill", "gearshape.fill", "briefcase.fill", "cart.fill", "creditcard.fill",
        "house.fill", "building.2.fill", "car.fill", "airplane", "globe", "map.fill",
        "calendar", "clock.fill", "bell.fill", "flag.fill", "tag.fill", "bookmark.fill",
        "lock.fill", "key.fill", "trash.fill", "archivebox.fill", "tray.full.fill",
        "person.fill", "person.2.fill", "gamecontroller.fill", "graduationcap.fill",
        "leaf.fill", "flame.fill"
    ]

    static func load(bundle: Bundle = .main) -> SymbolCatalog {
        let restricted = restrictedNames(bundle: bundle)
        let available = availableNames()
        let names = available.subtracting(restricted).sorted()
        let terms = (try? loadStringArrayDict(coreGlyphsResources.appendingPathComponent("symbol_search.plist"))) ?? [:]
        return SymbolCatalog(names: names, searchTerms: terms)
    }

    /// 名前の完全一致 > 前方一致 > 部分一致 > 検索語の前方一致、の順にランク付け。
    /// 各グループ内は `names` の並び (アルファベット順) を維持する。空なら popularNames を先頭に全件。
    func search(_ query: String, limit: Int = 240) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            let popular = Self.popularNames.filter { nameSet.contains($0) }
            return Array((popular + names.filter { !popular.contains($0) }).prefix(limit))
        }
        var exact: [String] = []
        var prefixMatches: [String] = []
        var substringMatches: [String] = []
        var termMatches: [String] = []
        for name in names {
            if name == q {
                exact.append(name)
            } else if name.hasPrefix(q) {
                prefixMatches.append(name)
            } else if name.contains(q) {
                substringMatches.append(name)
            } else if searchTerms[name]?.contains(where: { $0.lowercased().hasPrefix(q) }) ?? false {
                termMatches.append(name)
            }
        }
        return Array((exact + prefixMatches + substringMatches + termMatches).prefix(limit))
    }

    /// カタログに存在する記号名か。
    func contains(_ name: String) -> Bool { nameSet.contains(name) }

    /// 検索語 (symbol_search.plist) が term に一致する記号名。アルファベット順。
    func names(forTerm term: String) -> [String] {
        let t = term.lowercased()
        return searchTerms
            .filter { $0.value.contains { $0.lowercased() == t } }
            .map(\.key)
            .filter { nameSet.contains($0) }
            .sorted()
    }

    // MARK: - Loading

    /// CoreGlyphs の symbol_restrictions.strings。読めなければ同梱 restricted-symbols.txt。
    static func restrictedNames(bundle: Bundle) -> Set<String> {
        let live = coreGlyphsResources.appendingPathComponent("symbol_restrictions.strings")
        if let data = try? Data(contentsOf: live),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           !dict.isEmpty {
            return Set(dict.keys)
        }
        for b in [bundle, Bundle.main] {
            if let url = b.url(forResource: "restricted-symbols", withExtension: "txt"),
               let text = try? String(contentsOf: url) {
                return Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
            }
        }
        return []
    }

    /// name_availability.plist の symbols キー。読めなければ popularNames。
    private static func availableNames() -> Set<String> {
        let url = coreGlyphsResources.appendingPathComponent("name_availability.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let symbols = root["symbols"] as? [String: String] else {
            return Set(popularNames)
        }
        return Set(symbols.keys)
    }

    private static func loadStringArrayDict(_ url: URL) throws -> [String: [String]] {
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] ?? [:]
    }
}
