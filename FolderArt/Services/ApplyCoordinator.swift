import AppKit

struct ApplyFailure: Identifiable {
    let id = UUID()
    let folder: URL
    let reason: String
}

struct ApplyOutcome {
    let succeeded: [URL]
    let failed: [ApplyFailure]

    /// 一部失敗のときだけ文言を返す。全成功なら nil。
    var summary: String? {
        guard !failed.isEmpty else { return nil }
        let lines = failed.map { "・\($0.folder.lastPathComponent): \($0.reason)" }.joined(separator: "\n")
        return String(localized: "\(succeeded.count) 件成功、\(failed.count) 件失敗") + "\n\n" + lines
    }
}

enum ApplyError: LocalizedError {
    case composeFailed
    case bookmarkUnavailable
    case journalFailed(Error)

    var errorDescription: String? {
        switch self {
        case .composeFailed:       return String(localized: "アイコンの合成に失敗しました")
        case .bookmarkUnavailable: return String(localized: "フォルダーへのアクセスが無効になっています。")
        case .journalFailed(let e): return String(localized: "適用の控えを書けませんでした: \(e.localizedDescription)")
        }
    }
}

/// 1 つのオーバーレイを複数フォルダに適用する。1 件の失敗で止めず、結果を集めて返す。
@MainActor
final class ApplyCoordinator {
    private let history: HistoryStore
    private let iconManager: FolderIconManager

    init(history: HistoryStore, iconManager: FolderIconManager = FolderIconManager()) {
        self.history = history
        self.iconManager = iconManager
    }

    func apply(
        overlayImage: NSImage,
        overlay: Overlay,
        settings: CompositionSettings,
        to folders: [URL],
        progress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> ApplyOutcome {
        // 合成は 1 回だけ (512px 1 枚なのでメインで同期的に描いて問題ない)
        guard let icon = IconComposer.compose(overlay: overlayImage, settings: settings,
                                              fillsWhenClipped: overlay.fillsFolderWhenClipped) else {
            let failures = folders.map { ApplyFailure(folder: $0, reason: ApplyError.composeFailed.localizedDescription) }
            return ApplyOutcome(succeeded: [], failed: failures)
        }

        struct Applied {
            let folder: URL
            let task: IconTask
            let previousIcon: NSImage?
            let createdBackup: Bool
        }
        var applied: [Applied] = []
        var failed: [ApplyFailure] = []
        var seenFileIDs = Set<String>()
        // 前回、履歴の保存前に終了して回収できなかった控えがあれば引き継ぐ (上書きして失わない)
        let carried = history.pendingJournal()
        let total = folders.count

        for (index, folder) in folders.enumerated() {
            // 同じ実体のフォルダが別の path (実パスとシンボリックリンクなど) で 2 回来たら 2 回目は飛ばす。
            // 進むと 1 回目が付けたアイコンを「元のアイコン」としてバックアップしてしまう
            if let id = FileIdentity.make(for: folder), !seenFileIDs.insert(id).inserted {
                progress(index + 1, total)
                continue
            }
            var backupURL: URL?
            // 今回の適用で新たにバックアップを作った場合だけ true。既存のバックアップ
            // (再適用時に履歴から引き継いだもの) を失敗時に消してしまわないための区別
            var createdBackup = false
            // 控えに書けずアイコンを戻そうとして戻せなかった (FolderArt のアイコンが残っている)
            var rollbackFailed = false
            // 履歴の保存 (最後にまとめて 1 回) が失敗したときの巻き戻し先として使う。
            // ここで撮る時点ではまだ何も変更していない
            let previousIcon = snapshotIcon(of: folder)
            let fileID = FileIdentity.make(for: folder)
            do {
                let existing = history.task(forFolderPath: folder.standardizedFileURL.path, fileID: fileID)
                if let existing {
                    // 再適用: 最初の適用時に記録した元アイコン (nil = 元は標準アイコン) をそのまま引き継ぐ。
                    // ここで backupCurrentIcon を呼ぶと、前回 FolderArt が付けた Icon\r を
                    // 「元のアイコン」として誤って記録してしまう
                    backupURL = existing.backupPath.map { URL(fileURLWithPath: $0) }
                } else {
                    // バックアップの鍵は同一性 (fileID)。移動後に同じ場所へ作った別のフォルダが古いバックアップを拾わない
                    let hadBackup = iconManager.backupExists(for: folder, fileID: fileID)
                    backupURL = try iconManager.backupCurrentIcon(for: folder, fileID: fileID)
                    createdBackup = !hadBackup && backupURL != nil
                }
                try iconManager.applyIcon(icon, to: folder)
                // ブックマークは再起動後のリセット用。新規作成に失敗しても、再適用なら以前の
                // ブックマークを引き継ぐ。どちらも無ければ空 Data で記録し、適用自体は成功扱い
                let bookmark = Self.bookmarkToRecord(
                    new: try? BookmarkManager.createBookmark(for: folder),
                    existing: existing?.bookmarkData
                )
                let task = IconTask(
                    folderPath: folder.standardizedFileURL.path,
                    bookmarkData: bookmark,
                    backupPath: backupURL?.path,
                    overlay: overlay,
                    settings: settings,
                    fileID: fileID
                )
                // 履歴の保存は最後に 1 回なので、その前に終了してもアイコンだけ変わって行が残らないよう、
                // 成功した行を控えに書く (次回起動時に履歴へ取り込む)。控えに書けなければ (ディスク満杯など)
                // 進まずにアイコンを戻し、このフォルダは失敗にする
                do {
                    try history.journal(carried + applied.map(\.task) + [task])
                } catch {
                    // 戻せなかったら FolderArt のアイコンが残るので、元アイコンの唯一の控えであるバックアップは消さない
                    rollbackFailed = !NSWorkspace.shared.setIcon(previousIcon, forFile: folder.path, options: [])
                    throw ApplyError.journalFailed(error)
                }
                applied.append(Applied(folder: folder, task: task, previousIcon: previousIcon, createdBackup: createdBackup))
            } catch {
                // ここに来る時点ではフォルダのアイコンは変更前の状態 (バックアップ作成かアイコンの適用自体が
                // 失敗したか、控えに書けずに戻した)。今回新たに作ったバックアップだけ、使われないまま残さず消す
                // (最終保存の巻き戻しと同じ規則: 戻せなかったときは残す)
                if Self.shouldRemoveFreshBackup(createdBackup: createdBackup, rollbackSucceeded: !rollbackFailed) {
                    iconManager.removeBackup(for: folder, fileID: fileID)
                }
                var reason = error.localizedDescription
                if rollbackFailed { reason += " / 巻き戻し失敗: \(FolderIconError.resetFailed(folder).localizedDescription)" }
                failed.append(ApplyFailure(folder: folder, reason: reason))
            }
            progress(index + 1, total)
            await Task.yield()   // 進捗表示を描画させる
        }

        // 履歴は最後に 1 回だけ保存 (引き継いだ控えの行も一緒に)。失敗したら、この回に成功した全フォルダを直前の状態に戻す
        do {
            try history.upsertAll(carried + applied.map(\.task))
            history.clearJournal()
        } catch {
            // 今回の分は巻き戻すので控えから外す。引き継いだ前回の分は失わずに残す
            if carried.isEmpty { history.clearJournal() } else { try? history.journal(carried) }
            let base = String(localized: "履歴の保存に失敗しました: \(error.localizedDescription)")
            for item in applied {
                var reason = base
                let rollbackSucceeded = NSWorkspace.shared.setIcon(item.previousIcon, forFile: item.folder.path, options: [])
                if !rollbackSucceeded { reason += " / 巻き戻し失敗: \(FolderIconError.resetFailed(item.folder).localizedDescription)" }
                if Self.shouldRemoveFreshBackup(createdBackup: item.createdBackup, rollbackSucceeded: rollbackSucceeded) {
                    iconManager.removeBackup(for: item.folder, fileID: item.task.fileID)
                }
                failed.append(ApplyFailure(folder: item.folder, reason: reason))
            }
            return ApplyOutcome(succeeded: [], failed: failed)
        }
        return ApplyOutcome(succeeded: applied.map(\.folder), failed: failed)
    }

    /// 記録するブックマークを決める純粋関数。新規作成に成功すればそれを使い、失敗したら
    /// 再適用で引き継いだ既存のブックマークを使う。どちらも無ければ空 Data。
    static func bookmarkToRecord(new: Data?, existing: Data?) -> Data {
        new ?? existing ?? Data()
    }

    /// 新しく作ったバックアップを消してよいかどうかを判定する純粋関数。
    /// 巻き戻し (setIcon) に失敗した場合は、そのバックアップだけがユーザーの元アイコンを
    /// 復元できる手がかりになるため、たとえ今回新規に作ったものでも残す。
    static func shouldRemoveFreshBackup(createdBackup: Bool, rollbackSucceeded: Bool) -> Bool {
        createdBackup && rollbackSucceeded
    }

    /// 適用直前のアイコンをビットマップに焼き取る。カスタムアイコンが無ければ nil
    /// (nil をそのまま setIcon に渡すとカスタムアイコンの削除になる)。
    /// NSWorkspace の返すアイコンは遅延生成で、後からアイコンを書き換えると中身が変わって
    /// しまうため、その場で確定させる必要がある。
    private func snapshotIcon(of folder: URL) -> NSImage? {
        guard FileManager.default.fileExists(atPath: folder.appendingPathComponent("Icon\r").path) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: folder.path)
        return BitmapCanvas.draw(size: IconComposer.iconSize) { size in
            icon.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .sourceOver, fraction: 1)
        }
    }

    /// 履歴の 1 行をリセット (別セッション再開用: ブックマーク経由)
    func reset(_ task: IconTask) throws {
        guard !task.bookmarkData.isEmpty,
              let url = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            throw ApplyError.bookmarkUnavailable
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        try iconManager.resetIcon(for: url, backupURL: task.backupPath.map { URL(fileURLWithPath: $0) })
        try history.remove(task)
        iconManager.removeBackup(atBackupPath: task.backupPath)
    }

    /// 同一セッション用: URL を直接使ってリセット。
    /// 履歴に無いフォルダは FolderArt が触っていないので何もしない
    /// (手で設定したカスタムアイコンを消してしまわないため)。
    func reset(folder: URL) throws {
        let path = folder.standardizedFileURL.path
        // 移動・改名したフォルダも fileID で見つける (履歴の行は古い path のまま)
        guard let task = history.task(forFolderPath: path, fileID: FileIdentity.make(for: folder)) else { return }
        try iconManager.resetIcon(for: folder, backupURL: task.backupPath.map { URL(fileURLWithPath: $0) })
        try history.remove(task)
        iconManager.removeBackup(atBackupPath: task.backupPath)
    }
}
