import Foundation
import Combine

final class HistoryStore: ObservableObject {
    @Published private(set) var tasks: [IconTask] = []
    /// 起動時の読み込みに失敗した場合のエラー (UI がアラートに出す)
    private(set) var loadError: Error?

    private let store: CodableStore<[IconTask]>

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
            tasks = []
            return
        }
        // v1 から移行した行があれば v2 形式で保存し直す。失敗しても読めた履歴は捨てず、loadError で知らせる
        if !tasks.isEmpty {
            do { try store.save(tasks) } catch { loadError = error }
        }
    }

    /// 同じ folderPath の行があれば置き換え、先頭に置く
    func upsert(_ task: IconTask) throws {
        var updated = tasks.filter { $0.folderPath != task.folderPath }
        updated.insert(task, at: 0)
        try store.save(updated)
        tasks = updated
    }

    func remove(_ task: IconTask) throws {
        let updated = tasks.filter { $0.id != task.id }
        try store.save(updated)
        tasks = updated
    }

    func task(forFolderPath path: String) -> IconTask? {
        tasks.first { $0.folderPath == path }
    }

    var referencedAssetIDs: Set<UUID> {
        Set(tasks.compactMap { $0.overlay.assetID })
    }
}
