import SwiftUI

struct ContentView: View {
    // AppModel が子オブジェクトの objectWillChange を転送するので、これ 1 つで再描画される
    @StateObject private var model = AppModel()
    @State private var showHistory = false
    @State private var showError = false
    @State private var windowTargeted = false

    /// `model.overlay` は let なので `$model.overlay.settings` は書けない。手で Binding を作る。
    private var settingsBinding: Binding<CompositionSettings> {
        Binding(get: { model.overlay.settings }, set: { model.overlay.settings = $0 })
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack(alignment: .top, spacing: 12) {
                FolderListView(
                    selection: model.folders,
                    onAdd: { model.selectFoldersWithPanel() },
                    onDrop: { model.handleDroppedURLs($0) },
                    isApplying: model.isApplying
                )
                .frame(minWidth: 240)

                OverlayPickerView(
                    state: model.overlay,
                    catalog: SymbolCatalog.shared,
                    onPickImage: { model.selectImageWithPanel() },
                    onDrop: { model.handleDroppedURLs($0) }
                )
                .frame(minWidth: 380)
            }
            .frame(height: 260)
            .padding(12)

            PresetStripView(
                store: model.presets,
                assets: model.assets,
                canSave: model.overlay.overlay != nil,
                isApplying: model.isApplying,
                onSave: { model.saveCurrentAsPreset() },
                onApply: { model.applyPreset($0) },
                onRename: { model.renamePreset($0, to: $1) },
                onRemove: { model.removePreset($0) }
            )
            Divider()

            HStack(alignment: .top, spacing: 12) {
                ControlsView(settings: settingsBinding,
                             showsTint: model.overlay.activeTab == .symbol || model.overlay.activeTab == .text,
                             sizeLockedByFill: model.overlay.activeTab == .image)
                    .frame(maxWidth: .infinity)
                PreviewView(image: model.overlay.previewImage,
                            placeholder: "フォルダーと\n重ねるものを選択")
                    .frame(width: 200)
            }
            .padding(.vertical, 12)
            // hover の拡大プレビューを下のアクションバーより手前に出す
            // (PreviewView 内側の zIndex は外側 VStack の兄弟には効かない)
            .zIndex(1)
            Divider()

            actionBar
        }
        .frame(minWidth: 760, minHeight: 720)
        .background(
            // 余白へのドロップ用。.background なので内側の受け口 (リストと画像タブ) が上に来て優先される
            FileDropReceiver(
                isTargeted: $windowTargeted,
                accepts: { $0.contains { DropZoneView.isDirectory($0) || DropZoneView.isImage($0) } },
                onDrop: { model.handleDroppedURLs($0) }
            )
        )
        .sheet(isPresented: $showHistory) {
            HistoryView(
                historyStore: model.history,
                onReset: { task in model.reset(task: task); showHistory = false },
                onReapply: { task in model.restore(from: task); showHistory = false },
                isApplying: model.isApplying
            )
        }
        // onChange は初期値では発火しない。起動時点で既に出ている読み込みエラーはここで拾う
        .onAppear { showError = (model.errorMessage != nil) }
        .onChange(of: model.errorMessage) { msg in showError = (msg != nil) }
        .alert("お知らせ", isPresented: $showError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            Text("FolderArt").font(.headline)
            Spacer()
            Button { showHistory = true } label: { Label("履歴", systemImage: "clock") }
                .buttonStyle(.borderless)
                .disabled(model.isApplying)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack {
            Button { model.resetTargets() } label: { Label("リセット", systemImage: "arrow.uturn.backward") }
                .disabled(!model.canReset)
                .help(Text("適用先のフォルダーのアイコンを元に戻す"))

            Button { model.folders.removeAll() } label: { Label("リストを空にする", systemImage: "xmark.bin") }
                .disabled(model.folders.isEmpty || model.isApplying)

            Spacer()

            if let p = model.progress {
                Text("\(p.done) / \(p.total)").font(.callout).monospacedDigit().foregroundColor(.secondary)
            }

            Button { Task { await model.apply() } } label: {
                Label(model.applyButtonTitle, systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canApply)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}
