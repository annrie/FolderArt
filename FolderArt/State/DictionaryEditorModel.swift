import Foundation
import Combine

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
    /// 現在のファイルが読み込めない状態 (壊れ/上限超)。黙って上書きするとデータを失うので、明示確認を要する。
    @Published private(set) var loadFailed = false
    /// 「読み込めないファイルを上書きしていいか」の確認をビューに促すフラグ。
    @Published var pendingOverwriteUnreadable = false

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
        pendingOverwriteUnreadable = false
        isDirty = false
        selection = nil
        switch snapshot.result {
        case nil:
            rows = []                       // ファイル無し
            errorMessage = nil
            loadFailed = false
        case .success(let dict):
            rows = dict.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
            errorMessage = nil
            loadFailed = false
        case .failure(let error):
            rows = []
            errorMessage = error.localizedDescription
            loadFailed = true
        }
    }

    // MARK: - 編集操作 (実際に変化した時だけ isDirty を立てる)

    func addRow() {
        let row = Row(keys: [], symbol: nil, emoji: nil)
        rows.append(row); selection = row.id; isDirty = true
    }
    func deleteRows(_ ids: Set<Row.ID>) {
        let before = rows.count
        rows.removeAll { ids.contains($0.id) }
        guard rows.count != before else { return }
        isDirty = true
        if let sel = selection, ids.contains(sel) { selection = nil }
    }
    func addKey(_ raw: String, to id: Row.ID) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if !rows[i].keys.contains(key) { rows[i].keys.append(key); isDirty = true }
    }
    func removeKey(_ key: String, from id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }), rows[i].keys.contains(key) else { return }
        rows[i].keys.removeAll { $0 == key }
        isDirty = true
    }
    func setSymbol(_ name: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let newValue = (name?.isEmpty == true) ? nil : name
        guard rows[i].symbol != newValue else { return }
        rows[i].symbol = newValue
        isDirty = true
    }
    func setEmoji(_ emoji: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let e = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        let newValue = (e?.isEmpty == true) ? nil : e
        guard rows[i].emoji != newValue else { return }
        rows[i].emoji = newValue
        isDirty = true
    }

    // MARK: - 保存

    /// rows → [SuggestionEntry] → normalizedUser 検証 → 外部変更確認 → アトミック書き出し。
    /// 検証エラーは errorMessage にして false。外部変更があれば (force でなければ) pendingExternalChange=true で false。
    @discardableResult
    func save(force: Bool = false) -> Bool {
        let entries = rows.map { SuggestionEntry(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        // キーだけ・記号か絵文字だけの片方だけの項目は normalizedUser が黙って捨ててしまうので、
        // 完全に空の行 (キーも記号も絵文字も無い、＋ で足しただけの行) と区別してここで弾く。
        let hasIncompleteRow = entries.contains { entry in
            let hasKey = entry.keys.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let hasSymbolOrEmoji = (entry.symbol?.isEmpty == false) || (entry.emoji?.isEmpty == false)
            return hasKey != hasSymbolOrEmoji   // 片方だけ = 不完全 (両方無し=空行は従来どおり黙って捨てる)
        }
        guard !hasIncompleteRow else {
            errorMessage = String(localized: "各項目には「キー」と「記号または絵文字」の両方が必要です。不足している項目を完成させるか、削除してください。")
            return false
        }
        let normalized: SuggestionDictionary
        do {
            normalized = try SuggestionDictionary.normalizedUser(entries)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        if !force {
            if loadFailed {
                // 読み込めないファイルを黙って上書きすると元の内容を失う。明示確認を挟む。
                pendingOverwriteUnreadable = true
                return false
            }
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
            guard data.count <= SuggestionDictionary.userMaxFileBytes else {
                // load 側 (loadUserSnapshot) と同じ上限。ここで弾かないと保存は成功表示なのに
                // 本体の読み込みが tooLarge で拒否して同梱辞書に落ちる不整合になる。
                errorMessage = UserDictionaryError.tooLarge(data.count).localizedDescription
                return false
            }
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "提案辞書を保存できません: \(error.localizedDescription)")
            return false
        }
        loadedContentHash = SuggestionDictionary.loadUserSnapshot(at: url).contentHash
        isDirty = false
        pendingExternalChange = false
        loadFailed = false
        pendingOverwriteUnreadable = false
        // 正規化後の姿を表示に反映 (Row は新しい id を持つので選択は解除する)
        rows = normalized.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        selection = nil
        NotificationCenter.default.post(name: AppModel.userDictionaryEditedNotification, object: nil)
        return true
    }
}
