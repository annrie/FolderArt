import SwiftUI

@main
struct FolderArtApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 720)
    }
}
