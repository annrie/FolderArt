import AppKit

/// NSServices の提供オブジェクト。pboard からフォルダー URL を取り出し、AppModel に委譲する薄い層。
/// 実処理・エラー表示は AppModel 側。静かな 2 サービスの後始末 (静かな終了) は onSilentServiceFinished で通知する。
final class QuickActionProvider: NSObject {
    private let model: AppModel
    /// 静かなサービス (適用・戻す) が 1 つ完了するたびに呼ばれる。AppDelegate が「起動専用なら終了」を判断する。
    var onSilentServiceFinished: (() -> Void)?

    init(model: AppModel) { self.model = model }

    /// AppModel.directories(from:) と同じフィルタ (実在するディレクトリだけ、standardized で返す)。
    /// AppModel は @MainActor 隔離のため static メンバーもそちらに縛られ、ここ (nonisolated) からは
    /// 同期呼び出しできない。ロジックが軽い純関数なのでそのまま複製する
    /// (AppModel 側の各メソッドも受け取った URL を改めて同じ基準でフィルタするため、二重チェックになるだけで挙動は変わらない)。
    static func folderURLs(from pboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objs = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return objs.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url.standardizedFileURL
        }
    }

    @objc func openFoldersInFolderArt(_ pboard: NSPasteboard, userData: String?,
                                      error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in self.model.openFolders(urls) }
    }

    @objc func applyLastPreset(_ pboard: NSPasteboard, userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in
            switch await self.model.applyLastPreset(to: urls) {
            case .applied:
                break // 静かに成功 (合図は Finder のアイコン変化)。onSilentServiceFinished で静かに終了しうる
            case .noPreset:
                self.model.errorMessage = String(localized: "まだお気に入りを使っていません。まず FolderArt でお気に入りを適用してください。")
                NSApp.activate(ignoringOtherApps: true)
            case .failed(let message):
                self.model.errorMessage = message
                NSApp.activate(ignoringOtherApps: true)
            }
            self.onSilentServiceFinished?()
        }
    }

    @objc func resetIcon(_ pboard: NSPasteboard, userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in
            self.model.resetIcons(at: urls)
            self.onSilentServiceFinished?()
        }
    }
}
