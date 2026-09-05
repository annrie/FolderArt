import SwiftUI

/// 「選んで書き出す」の popover。チェックリストで選んだお気に入りだけを onExport に渡す。
/// 選択は ID だけを持ち、件数と書き出す配列は常に今のお気に入りから数える (表示中に削除されても食い違わない)
struct PresetExportPickerView: View {
    @ObservedObject var store: PresetStore
    let assets: AssetStore
    let onExport: ([Preset]) -> Void

    @State private var selection = PresetExportSelection()

    private var selectedPresets: [Preset] { selection.selected(from: store.presets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("お気に入りを選んで書き出す").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.presets) { preset in
                        Toggle(isOn: Binding(
                            get: { selection.isSelected(preset.id) },
                            set: { _ in selection.toggle(preset.id) }
                        )) {
                            HStack(spacing: 8) {
                                PresetChip(preset: preset, assets: assets)
                                Text(preset.name).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)
            HStack {
                Button("すべて選択") { selection.selectAll(store.presets) }
                Button("選択解除") { selection.clear() }
                    .disabled(selectedPresets.isEmpty)
                Spacer()
                Button { onExport(selectedPresets) } label: {
                    Text("書き出す (\(selectedPresets.count) 件)")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPresets.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 300)
        // 表示中にお気に入りが削除・読み込み・並び替えされたら、無くなった ID を捨てる
        .onChange(of: store.presets) { presets in selection.prune(to: presets) }
    }
}
