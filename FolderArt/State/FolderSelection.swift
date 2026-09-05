import Foundation
import Combine

/// 適用先フォルダのリストと、その中の選択。
@MainActor
final class FolderSelection: ObservableObject {
    @Published private(set) var folders: [URL] = []
    /// List の selection。要素は folders と同じ standardizedFileURL
    @Published var selectedIDs: Set<URL> = []

    var isEmpty: Bool { folders.isEmpty }

    /// 適用対象: 選択があれば選択分、無ければ全件
    var targets: [URL] {
        if selectedIDs.isEmpty { return folders }
        return folders.filter { selectedIDs.contains($0) }
    }

    /// 複数フォルダをまとめて追加する。$folders は (何か追加できたときに限り) 最後に 1 回だけ公開する。
    /// バッチのたびに毎回公開すると、それを購読して走査を始める側 (AppModel) が
    /// 追加のたびに前の走査を cancel してはまた開始する、という無駄な走査を繰り返してしまうため
    func add(_ urls: [URL]) {
        var updated = folders
        var existing = Set(updated)
        var didAdd = false
        for raw in urls {
            let url = raw.standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !existing.contains(url) else { continue }
            updated.append(url)
            existing.insert(url)
            didAdd = true
        }
        guard didAdd else { return }
        folders = updated
    }

    func remove(_ url: URL) {
        let target = url.standardizedFileURL
        folders.removeAll { $0 == target }
        selectedIDs.remove(target)
    }

    func removeAll() {
        folders = []
        selectedIDs = []
    }

    func clearSelection() {
        selectedIDs = []
    }
}
