import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published private(set) var tasks: [IconTask] = []

    private let storageURL: URL

    /// 本番用イニシャライザー（Application Support を使用）
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("FolderArt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(storageURL: dir.appendingPathComponent("history.json"))
    }

    /// テスト用イニシャライザー（任意の URL を指定可能）
    init(storageURL: URL) {
        self.storageURL = storageURL
        load()
    }

    func add(_ task: IconTask) {
        tasks.insert(task, at: 0)
        save()
    }

    func remove(_ task: IconTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([IconTask].self, from: data) else {
            return
        }
        tasks = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: storageURL)
    }
}
