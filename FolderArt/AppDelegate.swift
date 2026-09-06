import AppKit
import os

/// 共有 AppModel を所有し、NSServices を登録する。閉じた状態からサービスのためだけに
/// 起動された場合は、ウィンドウを出さず処理完了後に静かに終了する。
/// AppKit のデリゲートコールバックはメインスレッドで呼ばれる。@MainActor な AppModel を
/// 非同期を挟まず保持・初期化するため、このクラス自体も @MainActor にする
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let log = Logger(subsystem: "com.example.FolderArt", category: "quickaction")
    let model = AppModel()
    private lazy var provider = QuickActionProvider(model: model)

    /// ユーザーがウィンドウを出す前にサービスが呼ばれたら「起動専用」とみなす候補になる
    private var userOpenedWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        provider.onSilentServiceFinished = { [weak self] in self?.terminateIfLaunchedForServiceOnly() }
        provider.onOpenRequested = { [weak self] in self?.showMainWindow() }
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

    /// サービス「FolderArt で開く」で起動された場合、SwiftUI の Window はまだ生成されていないことがある
    /// (遅延生成)。生成されるまで次の runloop で数回リトライする
    func showMainWindow(attempt: Int = 0) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        if let w = NSApp.windows.first(where: { $0.canBecomeMain }) {
            w.makeKeyAndOrderFront(nil)
        } else if attempt < 20 {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in self?.showMainWindow(attempt: attempt + 1) }
        } else {
            log.error("showMainWindow: no window after 20 attempts")
        }
    }

    /// 「FolderArt で開く」やユーザー操作でウィンドウが出ていれば終了しない。
    /// 起動専用 (ウィンドウ未表示) なら静かに終了する。
    private func terminateIfLaunchedForServiceOnly() {
        guard !userOpenedWindow,
              !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        NSApp.terminate(nil)
    }
}
