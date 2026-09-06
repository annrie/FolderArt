import SwiftUI

@main
struct FolderArtApp: App {
    @StateObject private var language = LanguageSetting()

    var body: some Scene {
        // WindowGroup だと新規ウィンドウごとに別の AppModel が生成され、同じ資産ディレクトリを
        // 共有するため、後から開いたウィンドウの reapAssets() が先のウィンドウでまだ参照されて
        // いない画像を回収してしまう。単一ウィンドウに限定してこれを防ぐ
        Window("FolderArt", id: "main") {
            ContentView()
                .environmentObject(language)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 780)
        .commands {
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
            }
            // 「表示」メニューに「言語」サブメニュー (チェックマーク付きの 9 択)。選ぶと ContentView がアラートで再起動を促す
            CommandGroup(after: .toolbar) {
                Picker("言語", selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }
        }
    }
}
