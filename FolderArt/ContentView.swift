import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ContentViewModel()
    @State private var showHistory = false
    @State private var showError   = false

    var body: some View {
        VStack(spacing: 0) {

            // ツールバー
            HStack {
                Text("FolderArt")
                    .font(.headline)
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Label("履歴", systemImage: "clock")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // ドロップゾーン（上半分）
            HStack(spacing: 16) {
                DropZoneView(
                    mode: .folder,
                    selectedURL: vm.selectedFolderURL,
                    previewImage: vm.selectedFolderURL.map {
                        NSWorkspace.shared.icon(forFile: $0.path)
                    },
                    onDropURL: { url in vm.selectedFolderURL = url },
                    onTapButton: { vm.selectFolder() }
                )

                DropZoneView(
                    mode: .image,
                    selectedURL: vm.selectedImage != nil
                        ? URL(fileURLWithPath: vm.imageName)
                        : nil,
                    previewImage: vm.selectedImage,
                    onDropURL: { url in
                        if let img = NSImage(contentsOf: url) {
                            vm.selectedImage = img
                            vm.imageName = url.lastPathComponent
                        }
                    },
                    onTapButton: { vm.selectImage() }
                )
            }
            .padding()

            Divider()

            // 設定コントロール
            ControlsView(settings: $vm.settings)
                .padding(.vertical, 8)

            Divider()

            // プレビューエリア
            VStack(spacing: 8) {
                Text("プレビュー")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let preview = vm.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 128, height: 128)
                        .overlay(
                            Text("フォルダーと\n画像を選択")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        )
                }
            }
            .padding()

            Divider()

            // アクションボタン
            HStack {
                Button {
                    vm.resetCurrentIcon()
                } label: {
                    Label("リセット", systemImage: "arrow.uturn.backward")
                }
                .disabled(vm.selectedFolderURL == nil)

                Spacer()

                Button {
                    Task { await vm.applyIcon() }
                } label: {
                    Label(
                        vm.isApplying ? "適用中..." : "アイコンを適用",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canApply || vm.isApplying)
            }
            .padding()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                historyStore: vm.historyStore,
                onReset: { task in
                    vm.resetIcon(task: task)
                    showHistory = false
                }
            )
        }
        .onChange(of: vm.errorMessage) { msg in
            if msg != nil { showError = true }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
