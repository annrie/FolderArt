import SwiftUI

/// タブの上に出す提案の帯。高さ 36pt 固定 (候補が無くても空のまま高さを保つ)。
/// 4 つ入りきらないときは横スクロール (右へはみ出さない)
struct SuggestionStripView: View {
    let suggestions: [Suggestion]
    let assets: AssetStore
    let isApplying: Bool
    let onPick: (Suggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !suggestions.isEmpty {
                    Text("提案:").font(.caption).foregroundColor(.secondary)
                    ForEach(suggestions) { s in
                        // Button にしておくとキーボードと VoiceOver からも押せる
                        Button { onPick(s) } label: {
                            SuggestionChip(suggestion: s, assets: assets)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                        .opacity(isApplying ? 0.5 : 1)
                        .help(Text(s.reason))
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 36)
        }
        .frame(height: 36)
    }
}

/// 候補 1 つ分のチップ (28pt のサムネイル + 短いラベル)。サムネイルは 1 回だけ描いてキャッシュ。
private struct SuggestionChip: View {
    let suggestion: Suggestion
    let assets: AssetStore
    @State private var cached: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let image = cached {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "sparkles").foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            // 記号名やファイル名は長いことがあるので幅を抑えて中央を省略する
            Text(label).font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 120)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))
        .task(id: suggestion.id) { cached = thumbnail }
    }

    private var label: String {
        switch suggestion.kind {
        case .symbol(let s): return s
        case .emoji(let e):  return e
        case .text(let t):   return t
        case .preset(let p): return p.name
        case .image(let r):  return r.url.lastPathComponent
        }
    }

    /// 他のチップと同じ「フォルダに合成した見た目」。画像チップは走査で作ったサムネイル PNG から描く (AssetStore には無い)
    private var thumbnail: NSImage? {
        let settings: CompositionSettings
        let rendered: NSImage?
        let fills: Bool
        switch suggestion.kind {
        case .symbol(let s):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.symbol(name: s), settings: settings, side: 128, assets: assets)
        case .emoji(let e):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.emoji(e), settings: settings, side: 128, assets: assets)
        case .text(let t):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.text(t), settings: settings, side: 128, assets: assets)
        case .preset(let p):
            settings = p.settings; fills = p.overlay.fillsFolderWhenClipped
            rendered = OverlayRenderer.render(p.overlay, settings: settings, side: 128, assets: assets)
        case .image(let r):
            settings = CompositionSettings(); fills = true
            rendered = NSImage(data: r.thumbnailPNG).flatMap { OverlayRenderer.render(image: $0, side: 128) }
        }
        guard let rendered else { return nil }
        return IconComposer.compose(overlay: rendered, settings: settings, fillsWhenClipped: fills)
    }
}
