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

    func add(_ urls: [URL]) {
        var existing = Set(folders)
        for raw in urls {
            let url = raw.standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !existing.contains(url) else { continue }
            folders.append(url)
            existing.insert(url)
        }
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
