import SwiftUI

/// お気に入りの帯。チップはサムネイル、クリックで復元、右クリックで名前変更・削除。
struct PresetStripView: View {
    @ObservedObject var store: PresetStore
    let assets: AssetStore
    let canSave: Bool
    var isApplying: Bool = false
    let onSave: () -> Void
    let onApply: (Preset) -> Void
    let onRename: (Preset, String) -> Void
    let onRemove: (Preset) -> Void

    @State private var renaming: Preset?
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("お気に入り").font(.callout).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.presets) { preset in
                        PresetChip(preset: preset, assets: assets)
                            .onTapGesture { guard !isApplying else { return }; onApply(preset) }
                            .contextMenu {
                                Button("名前を変更…") { newName = preset.name; renaming = preset }
                                    .disabled(isApplying)
                                Button("削除", role: .destructive) { onRemove(preset) }
                                    .disabled(isApplying)
                            }
                            .help(Text(preset.name))
                    }
                    if store.presets.isEmpty {
                        Text("★ を押すと今の見た目を保存できます").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Button { onSave() } label: { Image(systemName: "star") }
                .buttonStyle(.borderless)
                .disabled(!canSave || isApplying)
                .help(Text("今の見た目をお気に入りに保存"))
        }
        .frame(height: 56)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(item: $renaming) { preset in
            VStack(spacing: 12) {
                Text("お気に入りの名前").font(.headline)
                TextField("名前", text: $newName).textFieldStyle(.roundedBorder).frame(width: 240)
                HStack {
                    Button("キャンセル") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button("保存") { onRename(preset, newName); renaming = nil }
                        .keyboardShortcut(.defaultAction).disabled(newName.isEmpty)
                }
            }
            .padding(20)
        }
    }
}

private struct PresetChip: View {
    let preset: Preset
    let assets: AssetStore

    @State private var cached: NSImage?

    var body: some View {
        Group {
            if let cached {
                Image(nsImage: cached).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed").foregroundColor(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
        .task(id: preset.id) { cached = thumbnail }
    }

    /// 128px で合成した小さなサムネイル
    private var thumbnail: NSImage? {
        guard let rendered = OverlayRenderer.render(preset.overlay, settings: preset.settings, side: 128, assets: assets),
              let composed = IconComposer.compose(overlay: rendered, settings: preset.settings,
                                                  fillsWhenClipped: preset.overlay.fillsFolderWhenClipped) else { return nil }
        return composed
    }
}
