import Foundation

/// 起動時の掃除。失敗は無視する (次回また試す)。
///
/// バックアップの掃除は「候補の列挙 (backupCandidates)」と「削除 (removeBackupDirectories)」に分かれている。
/// 列挙はメインの外で行ってよいが、削除は呼び出し側 (AppModel) がメインアクターで最新の履歴と
/// 照合してから行う。列挙から削除までの間に適用が既存のバックアップを再利用して履歴に載せることが
/// あり、そのまま消すと履歴が消えたバックアップを指してしまうため。
enum MaintenanceSweep {
    struct Result: Equatable {
        var backupsRemoved: Int
        var corruptFilesRemoved: Int
    }

    static let corruptFileMaxAge: TimeInterval = 30 * 24 * 60 * 60

    /// 列挙と削除をまとめて行う (テストと単純な呼び出し用)
    static func run(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                    backupDirectory: URL, appSupportDirectory: URL, now: Date = Date()) -> Result {
        let candidates = backupCandidates(referencedBackupPaths: referencedBackupPaths, historyLoaded: historyLoaded,
                                          backupDirectory: backupDirectory, now: now)
        let backups = removeBackupDirectories(candidates, stillReferencedBackupPaths: referencedBackupPaths)
        let corrupt = removeOldCorruptFiles(in: appSupportDirectory, now: now)
        return Result(backupsRemoved: backups, corruptFilesRemoved: corrupt)
    }

    /// どの履歴行からも参照されないバックアップディレクトリを列挙する (まだ消さない)。
    /// 履歴が読めていないときは空。ディレクトリ以外 (.DS_Store など)、作成日時が取れないもの、
    /// 起動時刻 (now) 以降に作られたもの (今のセッションのもの) は候補にしない
    static func backupCandidates(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                                 backupDirectory: URL, now: Date) -> [URL] {
        guard historyLoaded else { return [] }
        let referenced = referencedDirectories(referencedBackupPaths)
        let keys: Set<URLResourceKey> = [.isDirectoryKey, .creationDateKey]
        let children = (try? FileManager.default.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: Array(keys))) ?? []
        return children.filter { dir in
            guard !referenced.contains(dir.standardizedFileURL.path) else { return false }
            let values = try? dir.resourceValues(forKeys: keys)
            guard values?.isDirectory == true else { return false }
            guard let created = values?.creationDate, created < now else { return false }
            return true
        }
    }

    /// 候補のうち、今の履歴からも参照されていないものだけ消して、消した数を返す
    @discardableResult
    static func removeBackupDirectories(_ candidates: [URL], stillReferencedBackupPaths: Set<String>) -> Int {
        let referenced = referencedDirectories(stillReferencedBackupPaths)
        var count = 0
        for dir in candidates where !referenced.contains(dir.standardizedFileURL.path) {
            if (try? FileManager.default.removeItem(at: dir)) != nil { count += 1 }
        }
        return count
    }

    /// 30 日より古い隔離ファイル (CodableStore が作る `<name>.json.corrupt-yyyyMMdd-HHmmss`) を消す
    @discardableResult
    static func removeOldCorruptFiles(in appSupportDirectory: URL, now: Date) -> Int {
        let files = (try? FileManager.default.contentsOfDirectory(at: appSupportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        var count = 0
        for file in files where isQuarantineFileName(file.lastPathComponent) {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(modified) > corruptFileMaxAge, (try? FileManager.default.removeItem(at: file)) != nil {
                count += 1
            }
        }
        return count
    }

    /// `<name>.json.corrupt-yyyyMMdd-HHmmss` の形だけを隔離ファイルとみなす (それ以外の ".corrupt-" は触らない)
    static func isQuarantineFileName(_ name: String) -> Bool {
        guard let range = name.range(of: ".json.corrupt-"), range.lowerBound > name.startIndex else { return false }
        let stamp = name[range.upperBound...]                       // yyyyMMdd-HHmmss
        guard stamp.count == 15, stamp.dropFirst(8).first == "-" else { return false }
        let digits = String(stamp.prefix(8)) + String(stamp.dropFirst(9))
        return digits.allSatisfy { $0.isASCII && $0.isNumber }
    }

    /// backupPath (…/backups/<key>/original.png) の親ディレクトリの集合。列挙側と同じ正規化
    private static func referencedDirectories(_ backupPaths: Set<String>) -> Set<String> {
        Set(backupPaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path })
    }
}
