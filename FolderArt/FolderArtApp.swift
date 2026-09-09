import SwiftUI

@main
struct FolderArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var language = LanguageSetting()

    var body: some Scene {
        // WindowGroup だと新規ウィンドウごとに別の AppModel が生成され、同じ資産ディレクトリを
        // 共有するため、後から開いたウィンドウの reapAssets() が先のウィンドウでまだ参照されて
        // いない画像を回収してしまう。単一ウィンドウに限定してこれを防ぐ。
        // AppModel は AppDelegate が所有し、NSServices からも同じインスタンスを操作できるようにする
        Window("FolderArt", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)
                .environmentObject(language)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 780)
        .commands {
            FolderArtFileCommands()
            // 「表示」メニューに「言語」サブメニュー (チェックマーク付きの 9 択)。選ぶと ContentView がアラートで再起動を促す
            CommandGroup(after: .toolbar) {
                Picker("言語", selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }
        }

        // 提案辞書エディタ専用ウィンドウ。開くのは FolderArtFileCommands (openWindow を直接呼ぶ)。
        // メインウィンドウを閉じていても Commands はアプリ生存中ずっと存在するので、そちらに置く
        Window("提案辞書の編集", id: "dictionary-editor") {
            DictionaryEditorView(url: appDelegate.model.userDictionaryURL)
                .environmentObject(language)
        }
        .windowResizability(.contentMinSize)
        .defaultSize(width: 720, height: 520)
    }
}

/// 「ファイル」メニューへの追加項目。`openWindow` は Scene/View の環境値だが、`Commands` に
/// 準拠した構造体にすれば `@Environment` で受け取れる (View と同じくシーンの環境から供給される)。
/// これにより「提案辞書を編集…」はメインウィンドウの有無に関係なく直接ウィンドウを開ける
/// (以前は Notification を post して ContentView が受けていたため、メインウィンドウを閉じると効かなかった)
struct FolderArtFileCommands: Commands {
    @Environment(\.openWindow) private var openWindow

    var body: some Commands {
        CommandGroup(after: .importExport) {
            Button("お気に入りのパックを書き出す…") {
                NotificationCenter.default.post(name: AppModel.exportPackNotification, object: nil)
            }
            Button("お気に入りのパックを読み込む…") {
                NotificationCenter.default.post(name: AppModel.importPackNotification, object: nil)
            }
            Button("提案辞書を開く…") {
                NotificationCenter.default.post(name: AppModel.revealUserDictionaryNotification, object: nil)
            }
            Button("提案辞書を編集…") {
                openWindow(id: "dictionary-editor")
            }
        }
    }
}
