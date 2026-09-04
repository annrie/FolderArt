import Foundation
import Combine

final class HistoryStore: ObservableObject {
    @Published private(set) var tasks: [IconTask] = []
    /// 起動時の読み込みに失敗した場合のエラー (UI がアラートに出す)
    private(set) var loadError: Error?

    private let store: CodableStore<[IconTask]>
    /// 壊れたファイルを退避してから保存する必要があるか (最初の保存で 1 回だけ)
    private var needsQuarantine = false
    /// 保存した回数 (テスト用)
    private(set) var saveCount = 0

    /// ~/Library/Application Support/FolderArt
    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FolderArt")
    }

    convenience init() {
        self.init(storageURL: Self.appSupportDirectory.appendingPathComponent("history.json"))
    }

    init(storageURL: URL) {
        store = CodableStore(fileURL: storageURL)
        do {
            tasks = try store.load() ?? []
        } catch {
            loadError = error
            needsQuarantine = true   // 読めなかった中身を次の保存で黙って消さない
            tasks = []
            return
        }
        // v1 から移行した行があれば v2 形式で保存し直す。失敗しても読めた履歴は捨てず、loadError で知らせる
        if !tasks.isEmpty {
            do { try store.save(tasks) } catch { loadError = error }
        }
        // 一括適用の途中で終了した (アイコンは変わったが履歴の保存前だった) 行の控えがあれば取り込む
        recoverJournal()
    }

    // MARK: - 一括適用の途中経過の控え (ジャーナル)

    /// 一括適用は履歴を最後に 1 回だけ保存するので、その前にアプリが終了するとアイコンだけ変わって行が残らない。
    /// 成功した行をここに控えておき、次回起動時に履歴へ取り込む
    private var journalStore: CodableStore<[IconTask]> {
        CodableStore(fileURL: store.fileURL.deletingLastPathComponent().appendingPathComponent("history-pending.json"))
    }
    var journalURL: URL { journalStore.fileURL }

    func journal(_ pending: [IconTask]) throws { try journalStore.save(pending) }

    func clearJournal() { try? FileManager.default.removeItem(at: journalStore.fileURL) }

    /// 回収できていない控え (履歴が読めなかった起動で残したもの)。無ければ空
    func pendingJournal() -> [IconTask] { (try? journalStore.load()) ?? [] }

    /// 履歴が読めた起動でだけ取り込む (読めていない起動で取り込むと、控えの数行だけの履歴を書いてしまう)。
    /// 取り込めなければ控えは残し、次回また試す
    private func recoverJournal() {
        guard loadError == nil, let pending = try? journalStore.load(), !pending.isEmpty else { return }
        do {
            try upsertAll(pending)
            clearJournal()
        } catch {
            loadError = error
        }
    }

    /// 同じ folderPath か、同じ fileID (nil 同士は不一致) の行があれば置き換え、先頭に置く。
    /// 置き換えられる行が backupPath を持ち、新しい行が持たなければ引き継ぐ (元アイコンの記録を失わない)
    func upsert(_ task: IconTask) throws {
        let replaced = tasks.first { Self.sameFolder($0, task) }
        let merged = Self.inheritingBackupPath(task, from: replaced)
        var updated = tasks.filter { !Self.sameFolder($0, merged) }
        updated.insert(merged, at: 0)
        try save(updated)
        tasks = updated
    }

    /// 複数行を一度に反映して保存は 1 回。保存に失敗したらメモリ上の tasks も変えない。
    func upsertAll(_ newTasks: [IconTask]) throws {
        guard !newTasks.isEmpty else { return }
        // 同一バッチ内に同じフォルダ (sameFolder) が複数あれば 1 行にまとめ、後の行が勝つ。
        // upsert と同じパターン (先に消してから足す) で、フォルダごとの最後の出現位置の順序が残る
        var collapsed: [IconTask] = []
        for task in newTasks {
            collapsed.removeAll { Self.sameFolder($0, task) }
            collapsed.append(task)
        }
        let merged = collapsed.map { task in Self.inheritingBackupPath(task, from: tasks.first { Self.sameFolder($0, task) }) }
        var updated = tasks.filter { existing in !merged.contains { Self.sameFolder(existing, $0) } }
        updated.insert(contentsOf: merged, at: 0)
        try save(updated)
        tasks = updated
    }

    static func inheritingBackupPath(_ task: IconTask, from replaced: IconTask?) -> IconTask {
        guard task.backupPath == nil, let inherited = replaced?.backupPath else { return task }
        return task.withBackupPath(inherited)
    }

    /// 同じフォルダか。両方に fileID があるときはそれだけで判定する (path が同じでも別のフォルダ:
    /// 元のフォルダを移動した後、同じ場所に別のフォルダを作った場合)。片方でも無ければ path で判定
    static func sameFolder(_ a: IconTask, _ b: IconTask) -> Bool {
        if let x = a.fileID, let y = b.fileID { return x == y }
        return a.folderPath == b.folderPath
    }

    func remove(_ task: IconTask) throws {
        let updated = tasks.filter { $0.id != task.id }
        try save(updated)
        tasks = updated
    }

    /// 読み込みに失敗していた場合、最初の保存の前に壊れたファイルを退避する
    private func save(_ updated: [IconTask]) throws {
        if needsQuarantine {
            try store.quarantineIfPresent()
            needsQuarantine = false
        }
        try store.save(updated)
        saveCount += 1
    }

    func task(forFolderPath path: String) -> IconTask? {
        tasks.first { $0.folderPath == path }
    }

    /// path か fileID で一致する行。行と引数の両方に fileID があるときは fileID だけで判定する (sameFolder と同じ規則)
    func task(forFolderPath path: String, fileID: String?) -> IconTask? {
        tasks.first { row in
            if let mine = row.fileID, let theirs = fileID { return mine == theirs }
            return row.folderPath == path
        }
    }

    var referencedAssetIDs: Set<UUID> {
        Set(tasks.compactMap { $0.overlay.assetID })
    }
}
