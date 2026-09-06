import AppKit
import os

/// NSServices の提供オブジェクト。pboard からフォルダー URL を取り出し、AppModel に委譲する薄い層。
/// 実処理・エラー表示は AppModel 側。静かな 2 サービス (適用・戻す) が「エラー無しで完了した」ときだけ
/// onSilentServiceFinished で通知する。「開く」はウィンドウを前面化したいので onOpenRequested で通知する。
final class QuickActionProvider: NSObject {
    private let model: AppModel
    /// 実機でしか再現しない (サービス起動・サンドボックス・コールド起動固有の) 不具合の診断用
    private let log = Logger(subsystem: "com.example.FolderArt", category: "quickaction")
    /// 静かなサービス (適用・戻す) がエラー無く完了するたびに呼ばれる。AppDelegate が「起動専用なら終了」を判断する。
    /// エラーがあるとき (.noPreset / .failed / reset 失敗あり) は呼ばない: アラートを見せる前に
    /// 静かに終了して握りつぶしてしまうため
    var onSilentServiceFinished: (() -> Void)?
    /// 「FolderArt で開く」でフォルダーを読み込んだあとに呼ばれる。AppDelegate がウィンドウを前面化する
    var onOpenRequested: (() -> Void)?

    init(model: AppModel) { self.model = model }

    static func folderURLs(from pboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objs = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return AppModel.directories(from: objs)
    }

    @objc func openFoldersInFolderArt(_ pboard: NSPasteboard, userData: String?,
                                      error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        log.info("service \(#function) urls=\(urls.count)")
        Task { @MainActor in
            self.model.openFolders(urls)
            self.onOpenRequested?()
        }
    }

    @objc func applyLastPreset(_ pboard: NSPasteboard, userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        log.info("service \(#function) urls=\(urls.count)")
        Task { @MainActor in
            switch await self.model.applyLastPreset(to: urls) {
            case .applied:
                // 静かに成功 (合図は Finder のアイコン変化)。ここでだけ静かに終了してよい
                self.onSilentServiceFinished?()
            case .noPreset:
                self.model.errorMessage = String(localized: "まだお気に入りを使っていません。まず FolderArt でお気に入りを適用してください。")
                NSApp.activate(ignoringOtherApps: true)
            case .failed(let message):
                self.model.errorMessage = message
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }

    @objc func resetIcon(_ pboard: NSPasteboard, userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        log.info("service \(#function) urls=\(urls.count)")
        Task { @MainActor in
            if self.model.resetIcons(at: urls) {
                self.onSilentServiceFinished?()
            } else {
                NSApp.activate(ignoringOtherApps: true)
            }
        }
    }
}
