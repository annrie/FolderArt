import Foundation

/// 起動時の掃除。失敗は無視する (次回また試す)。
enum MaintenanceSweep {
    struct Result: Equatable {
        var backupsRemoved: Int
        var corruptFilesRemoved: Int
    }

    static let corruptFileMaxAge: TimeInterval = 30 * 24 * 60 * 60

    static func run(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                    backupDirectory: URL, appSupportDirectory: URL, now: Date = Date()) -> Result {
        var result = Result(backupsRemoved: 0, corruptFilesRemoved: 0)
        let fm = FileManager.default

        // 1. どの履歴行からも参照されないバックアップ (履歴が読めていないときは触らない)。
        // 起動時刻 (now) 以降に作られたものは今のセッションのものなので触らない
        // (履歴への保存がまだ済んでいないだけで、参照が付く直前かもしれない)
        if historyLoaded {
            let referencedDirs = Set(referencedBackupPaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path })
            let children = (try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey])) ?? []
            for dir in children where !referencedDirs.contains(dir.standardizedFileURL.path) {
                let values = try? dir.resourceValues(forKeys: [.isDirectoryKey, .creationDateKey])
                guard values?.isDirectory == true else { continue }   // ディレクトリ以外 (.DS_Store など) は対象外
                // 作成日時が取れない、または now 以降に作られたものは今のセッションのものとみなして消さない
                guard let created = values?.creationDate, created < now else { continue }
                if (try? fm.removeItem(at: dir)) != nil { result.backupsRemoved += 1 }
            }
        }

        // 2. 30 日より古い *.corrupt-* ファイル
        let files = (try? fm.contentsOfDirectory(at: appSupportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.contains(".corrupt-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(modified) > corruptFileMaxAge, (try? fm.removeItem(at: file)) != nil {
                result.corruptFilesRemoved += 1
            }
        }
        return result
    }
}
