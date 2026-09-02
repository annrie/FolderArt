import SwiftUI
import AppKit

extension OverlayState.Tab {
    var title: LocalizedStringKey {
        switch self {
        case .image:  return "画像"
        case .symbol: return "記号"
        case .emoji:  return "絵文字"
        case .text:   return "文字"
        }
    }
}

/// 「何を重ねるか」を選ぶ 4 タブ。設定スライダーとプレビューは 4 種類で共通。
struct OverlayPickerView: View {
    @ObservedObject var state: OverlayState
    let catalog: SymbolCatalog
    let onPickImage: () -> Void
    let onDropImage: (URL) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $state.activeTab) {
                ForEach(OverlayState.Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch state.activeTab {
            case .image:
                DropZoneView(
                    mode: .image,
                    selectedURL: state.imageAssetID.map { state.assets.url(for: $0) },
                    previewImage: state.imageAssetID.flatMap { state.assets.image(for: $0) },
                    onDropURLs: { urls in if let first = urls.first { onDropImage(first) } },
                    onTapButton: onPickImage
                )
            case .symbol:
                SymbolGridView(catalog: catalog, selected: $state.symbolName)
            case .emoji:
                VStack(spacing: 8) {
                    TextField("絵文字を入力", text: $state.emoji)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .onChange(of: state.emoji) { value in
                            // 1 文字 (1 書記素) に制限
                            if value.count > 1 { state.emoji = String(value.suffix(1)) }
                        }
                    Button {
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Label("絵文字パレットを開く", systemImage: "face.smiling")
                    }
                    .buttonStyle(.borderless)
                    Text("Ctrl + Cmd + Space でも開けます").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text:
                VStack(spacing: 8) {
                    TextField("文字を入力 (例: 2026, A, 案)", text: $state.text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 20))
                        .multilineTextAlignment(.center)
                    Text("長い文字は自動で縮小されます。2〜4 文字が読みやすい大きさです。")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
