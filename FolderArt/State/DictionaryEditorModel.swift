import Foundation

@MainActor
final class DictionaryEditorModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var keys: [String]
        var symbol: String?
        var emoji: String?
    }

    @Published private(set) var rows: [Row] = []
    @Published var selection: Row.ID?
    @Published private(set) var isDirty = false
    @Published var errorMessage: String?
    @Published var pendingExternalChange = false

    let catalog: SymbolCatalog
    private let url: URL
    private var loadedContentHash: Data?

    init(url: URL, catalog: SymbolCatalog = .shared) {
        self.url = url
        self.catalog = catalog
        reload()
    }

    /// 現在のファイルを読み直して rows を作る。無ければ空。読めない/壊れていれば errorMessage。
    func reload() {
        let snapshot = SuggestionDictionary.loadUserSnapshot(at: url)
        loadedContentHash = snapshot.contentHash
        pendingExternalChange = false
        isDirty = false
        selection = nil
        switch snapshot.result {
        case nil:
            rows = []                       // ファイル無し
        case .success(let dict):
            rows = dict.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        case .failure(let error):
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 編集操作 (すべて isDirty を立てる)

    func addRow() {
        let row = Row(keys: [], symbol: nil, emoji: nil)
        rows.append(row); selection = row.id; isDirty = true
    }
    func deleteRows(_ ids: Set<Row.ID>) {
        rows.removeAll { ids.contains($0.id) }; isDirty = true
        if let sel = selection, ids.contains(sel) { selection = nil }
    }
    func addKey(_ raw: String, to id: Row.ID) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if !rows[i].keys.contains(key) { rows[i].keys.append(key); isDirty = true }
    }
    func removeKey(_ key: String, from id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].keys.removeAll { $0 == key }; isDirty = true
    }
    func setSymbol(_ name: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].symbol = (name?.isEmpty == true) ? nil : name; isDirty = true
    }
    func setEmoji(_ emoji: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let e = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        rows[i].emoji = (e?.isEmpty == true) ? nil : e; isDirty = true
    }

    // MARK: - 保存

    /// rows → [SuggestionEntry] → normalizedUser 検証 → 外部変更確認 → アトミック書き出し。
    /// 検証エラーは errorMessage にして false。外部変更があれば (force でなければ) pendingExternalChange=true で false。
    @discardableResult
    func save(force: Bool = false) -> Bool {
        let entries = rows.map { SuggestionEntry(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        let normalized: SuggestionDictionary
        do {
            normalized = try SuggestionDictionary.normalizedUser(entries)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        if !force {
            let current = SuggestionDictionary.loadUserSnapshot(at: url).contentHash
            if let loaded = loadedContentHash, current != loaded {
                pendingExternalChange = true
                return false
            }
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(normalized.entries)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "提案辞書を保存できません: \(error.localizedDescription)")
            return false
        }
        loadedContentHash = SuggestionDictionary.loadUserSnapshot(at: url).contentHash
        isDirty = false
        pendingExternalChange = false
        // 正規化後の姿を表示に反映
        rows = normalized.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        NotificationCenter.default.post(name: AppModel.userDictionaryEditedNotification, object: nil)
        return true
    }
}
