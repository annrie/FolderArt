import AppKit

/// 共有 AppModel を所有し、NSServices を登録する。閉じた状態からサービスのためだけに
/// 起動された場合は、ウィンドウを出さず処理完了後に静かに終了する。
/// AppKit のデリゲートコールバックはメインスレッドで呼ばれる。@MainActor な AppModel を
/// 非同期を挟まず保持・初期化するため、このクラス自体も @MainActor にする
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var provider = QuickActionProvider(model: model)

    /// ユーザーがウィンドウを出す前にサービスが呼ばれたら「起動専用」とみなす候補になる
    private var userOpenedWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        provider.onSilentServiceFinished = { [weak self] in self?.terminateIfLaunchedForServiceOnly() }
        provider.onShowWindow = { [weak self] in self?.showMainWindow() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // ウィンドウが可視 = ユーザーが使っている。以後は静かな終了をしない
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            userOpenedWindow = true
        }
    }

    /// Dock アイコンクリックなどでウィンドウが無ければ前面化する (標準の Reopen ハンドラ)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { showMainWindow() }
        return true
    }

    /// サービス「FolderArt で開く」で起動された場合、SwiftUI の Window はまだ生成されていない。
    /// 実機ログで確認済み: NSApp.activate だけでは生成されず、reopen イベントでのみ生成される
    /// (Dock アイコンクリックと同じ経路)。ウィンドウが既にあればそれを前面化し、無ければ
    /// reopen を送って生成させる (createsNewApplicationInstance = false で既存インスタンスを再利用、
    /// 二重起動しない)
    func showMainWindow() {
        if let window = NSApp.windows.first(where: { $0.canBecomeMain }) {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
            window.makeKeyAndOrderFront(nil)
            return
        }
        NSApp.setActivationPolicy(.regular)
        let config = NSWorkspace.OpenConfiguration()
        config.createsNewApplicationInstance = false
        config.activates = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: config, completionHandler: nil)
    }

    /// 「FolderArt で開く」やユーザー操作でウィンドウが出ていれば終了しない。
    /// 起動専用 (ウィンドウ未表示) なら静かに終了する。
    private func terminateIfLaunchedForServiceOnly() {
        guard !userOpenedWindow,
              !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        NSApp.terminate(nil)
    }
}
