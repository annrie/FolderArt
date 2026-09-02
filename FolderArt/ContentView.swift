import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack {
            Text("FolderArt").font(.headline)
            Text("画面は再構築中")
        }
        .frame(minWidth: 760, minHeight: 720)
    }
}
