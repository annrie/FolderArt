import SwiftUI

/// 128px のプレビュー。hover でレイアウトを動かさずに拡大版と実寸列を上に重ねる。
struct PreviewView: View {
    let image: NSImage?
    let placeholder: LocalizedStringKey

    @State private var hovering = false
    private let sizes: [CGFloat] = [16, 32, 64, 128]

    var body: some View {
        VStack(spacing: 8) {
            Text("プレビュー").font(.caption).foregroundColor(.secondary)
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 128, height: 128)
                        .overlay(Text(placeholder).font(.caption).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center))
                }
            }
            .onHover { hovering = $0 && image != nil }
            .overlay(alignment: .bottomTrailing) {
                if hovering, let image {
                    VStack(spacing: 10) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: 256, height: 256)
                        HStack(alignment: .bottom, spacing: 14) {
                            ForEach(sizes, id: \.self) { side in
                                VStack(spacing: 2) {
                                    Image(nsImage: image).resizable().interpolation(.high)
                                        .frame(width: side, height: side)
                                    Text("\(Int(side))").font(.system(size: 9)).foregroundColor(.secondary)
                                }
                            }
                        }
                        Text("Finder での見え方 (px)").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial).shadow(radius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
                }
            }
            .zIndex(10)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}
