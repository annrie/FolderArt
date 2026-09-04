import Foundation

/// 起動時の掃除。失敗は無視する (次回また試す)。
///
/// バックアップの掃除は「候補の列挙 (backupCandidates)」と「片付け (removeBackupDirectories)」に分かれている。
/// 列挙はメインの外で行ってよいが、片付けは呼び出し側 (AppModel) がメインアクターで最新の履歴と
/// 照合してから行う。列挙から片付けまでの間に適用が既存のバックアップを再利用して履歴に載せることが
/// あり、そのまま消すと履歴が消えたバックアップを指してしまうため。
///
/// 片付けは完全削除ではなくゴミ箱へ移す (moveToTrash)。履歴は壊れることがあり、壊れた後に
/// 書き直された 1 行だけの history.json を「正」と信じて残り全部を消すと元アイコンが取り戻せなくなる。
/// 同じ理由で、history.json の隔離ファイルが残っている間はバックアップの片付けを丸ごと見送る。
enum MaintenanceSweep {
    struct Result: Equatable {
        var backupsRemoved: Int
        var corruptFilesRemoved: Int
    }

    static let corruptFileMaxAge: TimeInterval = 30 * 24 * 60 * 60

    /// 列挙と片付けをまとめて行う (テストと単純な呼び出し用)。
    /// moveToTrash はアプリでは常に true (テストがゴミ箱を汚さないための引数)
    static func run(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                    backupDirectory: URL, appSupportDirectory: URL, now: Date = Date(),
                    moveToTrash: Bool = true) -> Result {
        let trusted = historyLoaded && !hasHistoryQuarantine(in: appSupportDirectory)
        let candidates = backupCandidates(referencedBackupPaths: referencedBackupPaths, historyLoaded: trusted,
                                          backupDirectory: backupDirectory, now: now)
        let removed = removeBackupDirectories(candidates, stillReferencedBackupPaths: referencedBackupPaths,
                                              moveToTrash: moveToTrash)
        let corrupt = removeOldCorruptFiles(in: appSupportDirectory, now: now)
        return Result(backupsRemoved: removed.count, corruptFilesRemoved: corrupt)
    }

    /// `history.json` の隔離ファイルがあるうちは、今の履歴が全部そろっている保証がない
    /// (壊れた履歴を退避した直後の適用で 1 行だけの history.json が書かれる) ので、バックアップは触らない
    static func hasHistoryQuarantine(in appSupportDirectory: URL) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: appSupportDirectory.path)) ?? []
        return names.contains { $0.hasPrefix("history.json.corrupt-") && isQuarantineFileName($0) }
    }

    /// どの履歴行からも参照されないバックアップディレクトリを列挙する (まだ消さない)。
    /// 履歴が読めていない (信用できない) ときは空。ディレクトリ以外 (.DS_Store など)、作成日時が取れないもの、
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

    /// 候補のうち、今の履歴からも参照されていないものを片付け (ゴミ箱へ、または削除)、片付けたものの URL を返す
    /// (ゴミ箱に入れた場合は移動先の URL)
    @discardableResult
    static func removeBackupDirectories(_ candidates: [URL], stillReferencedBackupPaths: Set<String>,
                                        moveToTrash: Bool = true) -> [URL] {
        let referenced = referencedDirectories(stillReferencedBackupPaths)
        var removed: [URL] = []
        for dir in candidates where !referenced.contains(dir.standardizedFileURL.path) {
            if moveToTrash {
                var trashed: NSURL?
                if (try? FileManager.default.trashItem(at: dir, resultingItemURL: &trashed)) != nil {
                    removed.append((trashed as URL?) ?? dir)
                }
            } else if (try? FileManager.default.removeItem(at: dir)) != nil {
                removed.append(dir)
            }
        }
        return removed
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

    /// `<name>.json.corrupt-yyyyMMdd-HHmmss` (同一秒に 2 回退避したときは末尾に `-n`) の形だけを
    /// 隔離ファイルとみなす (それ以外の ".corrupt-" は触らない)。CodableStore.quarantineIfPresent と対
    static func isQuarantineFileName(_ name: String) -> Bool {
        guard let range = name.range(of: ".json.corrupt-"), range.lowerBound > name.startIndex else { return false }
        let parts = name[range.upperBound...].split(separator: "-", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count), parts[0].count == 8, parts[1].count == 6,
              parts.count == 2 || !parts[2].isEmpty else { return false }
        return parts.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
    }

    /// backupPath (…/backups/<key>/original.png) の親ディレクトリの集合。列挙側と同じ正規化
    private static func referencedDirectories(_ backupPaths: Set<String>) -> Set<String> {
        Set(backupPaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path })
    }
}
