import AppKit

/// 共有 AppModel を所有し、NSServices を登録する。閉じた状態からサービスのためだけに
/// 起動された場合は、ウィンドウを出さず処理完了後に静かに終了する。
/// AppKit のデリゲートコールバックはメインスレッドで呼ばれる。@MainActor な AppModel を
/// 非同期を挟まず保持・初期化するため、このクラス自体も @MainActor にする
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var provider = QuickActionProvider(model: model)

    /// メインウィンドウ (ContentView) を補助ウィンドウ (辞書エディタ) と確実に区別するための識別子。
    /// ContentView 側の MainWindowTagger が起動時にこの識別子を NSWindow へ付ける。
    static let mainWindowIdentifier = NSUserInterfaceItemIdentifier("folderart-main-window")

    /// タグ付けされたメインウィンドウ。エディタなど他の canBecomeMain なウィンドウは含まない。
    private var taggedMainWindow: NSWindow? {
        NSApp.windows.first { $0.identifier == Self.mainWindowIdentifier }
    }

    /// ユーザーがウィンドウを出す前にサービスが呼ばれたら「起動専用」とみなす候補になる
    private var userOpenedWindow = false
    /// showMainWindow が呼ばれたかどうかを同期的に記録する。reopen によるウィンドウ生成は非同期なので、
    /// 「開く」やエラー表示の要求と、別の静かなサービスの終了判定が交錯すると、ウィンドウがまだ
    /// できていない間に終了してしまいうる。要求した事実をここで先に記録して防ぐ
    private var windowRequested = false

    /// 辞書エディタの保存通知の監視トークン。ContentView (メインウィンドウ) ではなくここで持つのは、
    /// メインウィンドウを閉じてエディタだけ残した状態で保存されても確実に拾うため
    private var dictionaryEditedObserver: NSObjectProtocol?

    /// app レベルのメニューコマンド (書き出し/読み込み/辞書を開く) の監視トークン。
    /// メインウィンドウを閉じてエディタだけ残した状態でも効くよう、ContentView ではなくここで持つ。
    private var commandObservers: [NSObjectProtocol] = []

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        provider.onSilentServiceFinished = { [weak self] in self?.terminateIfLaunchedForServiceOnly() }
        provider.onShowWindow = { [weak self] in self?.showMainWindow() }

        // 通知は任意のスレッドから飛びうる。handleUserDictionaryEdited() は @MainActor な非同期メソッドなので Task で包む
        dictionaryEditedObserver = NotificationCenter.default.addObserver(
            forName: AppModel.userDictionaryEditedNotification, object: nil, queue: .main
        ) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in await self.model.handleUserDictionaryEdited() }
        }

        // メニューの「書き出し/読み込み/辞書を開く」も AppDelegate で観測する。
        // これらは以前 ContentView が受けていたため、メインウィンドウを閉じると効かなかった。
        // model のメソッドは @MainActor なので Task で包む (queue: .main のクロージャは非分離)。
        let center = NotificationCenter.default
        commandObservers = [
            center.addObserver(forName: AppModel.exportPackNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.model.exportPack() }
            },
            center.addObserver(forName: AppModel.importPackNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.model.importPackWithPanel() }
            },
            center.addObserver(forName: AppModel.revealUserDictionaryNotification, object: nil, queue: .main) { [weak self] _ in
                guard let self else { return }
                Task { @MainActor in self.model.revealUserDictionary() }
            },
        ]
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // ウィンドウが可視 = ユーザーが使っている。以後は静かな終了をしない
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            userOpenedWindow = true
        }
    }

    /// Dock アイコンクリックなどでウィンドウが無ければ前面化する (標準の Reopen ハンドラ)
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // 補助ウィンドウ (辞書エディタ) が可視でも flag は true になる。メインウィンドウ自体が
        // 出ていなければ (タグ付きが無い/不可視) 出す。エディタの可視性で抑止しない。
        if taggedMainWindow?.isVisible != true { showMainWindow() }
        return true
    }

    /// サービス「FolderArt で開く」で起動された場合、SwiftUI の Window はまだ生成されていない。
    /// 実機ログで確認済み: NSApp.activate だけでは生成されず、reopen イベントでのみ生成される
    /// (Dock アイコンクリックと同じ経路)。ウィンドウが既にあればそれを前面化し、無ければ
    /// reopen を送って生成させる (createsNewApplicationInstance = false で既存インスタンスを再利用、
    /// 二重起動しない)
    func showMainWindow() {
        windowRequested = true   // 同期的に記録 (reopen は非同期なので、終了ガードとの競合を防ぐ)
        if let window = taggedMainWindow {
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
