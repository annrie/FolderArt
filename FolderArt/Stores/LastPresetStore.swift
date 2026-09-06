import Foundation

/// 「最後に使ったお気に入り」の id を 1 ファイルに永続化する。読めない/壊れているときは nil。
struct LastPresetStore {
    private let store: CodableStore<UUID>

    init(storageURL: URL = HistoryStore.appSupportDirectory.appendingPathComponent("last-preset.json")) {
        store = CodableStore(fileURL: storageURL)
    }

    var id: UUID? {
        get { (try? store.load()) ?? nil }
        nonmutating set {
            if let value = newValue {
                try? store.save(value)
            } else if FileManager.default.fileExists(atPath: store.fileURL.path) {
                try? FileManager.default.removeItem(at: store.fileURL)
            }
        }
    }
}
