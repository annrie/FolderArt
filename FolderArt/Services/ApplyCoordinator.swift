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

    var errorDescription: String? {
        switch self {
        case .composeFailed:       return String(localized: "アイコンの合成に失敗しました")
        case .bookmarkUnavailable: return String(localized: "フォルダーへのアクセスが無効になっています。")
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
        guard let icon = IconComposer.compose(overlay: overlayImage, settings: settings) else {
            let failures = folders.map { ApplyFailure(folder: $0, reason: ApplyError.composeFailed.localizedDescription) }
            return ApplyOutcome(succeeded: [], failed: failures)
        }

        var succeeded: [URL] = []
        var failed: [ApplyFailure] = []
        let total = folders.count

        for (index, folder) in folders.enumerated() {
            var backupURL: URL?
            var iconApplied = false
            do {
                backupURL = try iconManager.backupCurrentIcon(for: folder)
                try iconManager.applyIcon(icon, to: folder)
                iconApplied = true
                // ブックマークは再起動後のリセット用。失敗しても適用は成功扱い (空 Data で記録)
                let bookmark = (try? BookmarkManager.createBookmark(for: folder)) ?? Data()
                let task = IconTask(
                    folderPath: folder.standardizedFileURL.path,
                    bookmarkData: bookmark,
                    backupPath: backupURL?.path,
                    overlay: overlay,
                    settings: settings
                )
                try history.upsert(task)
                succeeded.append(folder)
            } catch {
                // 履歴に残せなかったフォルダはアイコンを元に戻し、「失敗 = 変更なし」を保つ
                if iconApplied { iconManager.resetIcon(for: folder, backupURL: backupURL) }
                failed.append(ApplyFailure(folder: folder, reason: error.localizedDescription))
            }
            progress(index + 1, total)
            await Task.yield()   // 進捗表示を描画させる
        }
        return ApplyOutcome(succeeded: succeeded, failed: failed)
    }

    /// 履歴の 1 行をリセット (別セッション再開用: ブックマーク経由)
    func reset(_ task: IconTask) throws {
        guard !task.bookmarkData.isEmpty,
              let url = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            throw ApplyError.bookmarkUnavailable
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        iconManager.resetIcon(for: url, backupURL: task.backupPath.map { URL(fileURLWithPath: $0) })
        try history.remove(task)
    }

    /// 同一セッション用: URL を直接使ってリセット。
    /// 履歴に無いフォルダは FolderArt が触っていないので何もしない
    /// (手で設定したカスタムアイコンを消してしまわないため)。
    func reset(folder: URL) throws {
        let path = folder.standardizedFileURL.path
        guard let task = history.task(forFolderPath: path) else { return }
        iconManager.resetIcon(for: folder, backupURL: task.backupPath.map { URL(fileURLWithPath: $0) })
        try history.remove(task)
    }
}
