import SwiftUI

@main
struct FolderArtApp: App {
    var body: some Scene {
        // WindowGroup だと新規ウィンドウごとに別の AppModel が生成され、同じ資産ディレクトリを
        // 共有するため、後から開いたウィンドウの reapAssets() が先のウィンドウでまだ参照されて
        // いない画像を回収してしまう。単一ウィンドウに限定してこれを防ぐ
        Window("FolderArt", id: "main") {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 720)
        .commands {
            CommandGroup(after: .importExport) {
                Button("お気に入りのパックを書き出す…") {
                    NotificationCenter.default.post(name: AppModel.exportPackNotification, object: nil)
                }
                Button("お気に入りのパックを読み込む…") {
                    NotificationCenter.default.post(name: AppModel.importPackNotification, object: nil)
                }
            }
        }
    }
}
