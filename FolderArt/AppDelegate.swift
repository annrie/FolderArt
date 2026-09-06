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
    /// showMainWindow が呼ばれたかどうかを同期的に記録する。reopen によるウィンドウ生成は非同期なので、
    /// 「開く」やエラー表示の要求と、別の静かなサービスの終了判定が交錯すると、ウィンドウがまだ
    /// できていない間に終了してしまいうる。要求した事実をここで先に記録して防ぐ
    private var windowRequested = false

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
        windowRequested = true   // 同期的に記録 (reopen は非同期なので、終了ガードとの競合を防ぐ)
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
    /// 起動専用 (ウィンドウ未表示) なら静かに終了する。ただし起動時のエラー (壊れた保存データ等) が
    /// あれば、コールド起動でも見せる場所が要るので終了せずウィンドウを出す
    private func terminateIfLaunchedForServiceOnly() {
        if userOpenedWindow || windowRequested { return }
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) { return }
        if model.errorMessage != nil { showMainWindow(); return }
        NSApp.terminate(nil)
    }
}
