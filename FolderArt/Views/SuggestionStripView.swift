import SwiftUI

/// タブの上に出す提案の帯。高さ 36pt 固定 (候補が無くても空のまま高さを保つ)。
struct SuggestionStripView: View {
    let suggestions: [Suggestion]
    let assets: AssetStore
    let isApplying: Bool
    let onPick: (Suggestion) -> Void

    var body: some View {
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
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .padding(.horizontal, 4)
    }
}

/// 候補 1 つ分のチップ (32pt のサムネイル + 短いラベル)。サムネイルは 1 回だけ描いてキャッシュ。
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
            Text(label).font(.caption).lineLimit(1)
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

    private var thumbnail: NSImage? {
        let pair: (Overlay, CompositionSettings)? = {
            switch suggestion.kind {
            case .symbol(let s): return (.symbol(name: s), CompositionSettings())
            case .emoji(let e):  return (.emoji(e), CompositionSettings())
            case .text(let t):   return (.text(t), CompositionSettings())
            case .preset(let p): return (p.overlay, p.settings)
            case .image:         return nil
            }
        }()
        guard let (overlay, settings) = pair else { return nil }
        guard let rendered = OverlayRenderer.render(overlay, settings: settings, side: 128, assets: assets) else { return nil }
        return IconComposer.compose(overlay: rendered, settings: settings, fillsWhenClipped: overlay.fillsFolderWhenClipped)
    }
}
