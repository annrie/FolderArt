import AppKit

/// Overlay を透明背景の画像に描く。合成 (IconComposer) はこの出力だけを扱う。
/// 出力は基本的に正方形だが、切り抜き+中央配置の画像だけは元のアスペクト比を保った
/// 非正方形になる (calculateRect の AspectFill + verticalOffset にアスペクトごと委ねるため)。
enum OverlayRenderer {

    static func render(_ overlay: Overlay, settings: CompositionSettings,
                       side: CGFloat, assets: AssetStore) -> NSImage? {
        switch overlay {
        case .image(let id):
            guard let image = assets.image(for: id) else { return nil }
            // フォルダー形状に切り抜いて中央配置する設定では、IconComposer 側の calculateRect が
            // AspectFill でフォルダーいっぱいに敷き詰め、verticalOffset で上下にパンする。
            // ここで正方形に切り抜いてしまうと、パンする前に縦長/横長画像のはみ出し部分が
            // 失われてしまい、パンしてもフォルダーの外周が透明/背景色のまま抜けて見える。
            // そのためここでは切り抜かず、長辺を side に合わせて縮小するだけに留め、
            // アスペクト比の判断は IconComposer 側にそのまま渡す
            if settings.clipToFolderShape && settings.position == .center {
                return scaleToLongSide(image, side: side)
            }
            return fitIntoSquare(image, side: side)

        case .symbol(let name):
            guard let symbol = symbolImage(name: name, side: side, settings: settings) else { return nil }
            return fitIntoSquare(symbol, side: side, tint: settings.tintColor.nsColor)

        case .emoji(let s):
            return renderString(s, side: side, settings: settings, applyTint: false, useEmojiFont: true)

        case .text(let s):
            return renderString(s, side: side, settings: settings, applyTint: true)

        case .legacyImage:
            return nil
        }
    }

    // MARK: - Private

    /// アスペクト維持で正方形の中央に収める。tint があれば不透明部分をその色で塗る (sourceAtop)。
    private static func fitIntoSquare(_ image: NSImage, side: CGFloat, tint: NSColor? = nil) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = min(side / size.width, side / size.height)
        let drawSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return BitmapCanvas.draw(size: CGSize(width: side, height: side)) { canvas in
            image.draw(in: NSRect(origin: origin, size: drawSize),
                       from: NSRect(origin: .zero, size: size),
                       operation: .sourceOver, fraction: 1)
            if let tint {
                // テンプレート画像 (SF Symbols) は黒で描かれるので、アルファを保ったまま色を乗せる
                tint.setFill()
                NSRect(origin: .zero, size: canvas).fill(using: .sourceAtop)
            }
        }
    }

    /// アスペクト比を保ったまま長辺を side に合わせて縮小する (切り抜きも正方形化もしない)。
    private static func scaleToLongSide(_ image: NSImage, side: CGFloat) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = side / max(size.width, size.height)
        let scaledSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        return BitmapCanvas.draw(size: scaledSize) { _ in
            image.draw(in: NSRect(origin: .zero, size: scaledSize),
                       from: NSRect(origin: .zero, size: size),
                       operation: .sourceOver, fraction: 1)
        }
    }

    private static func symbolImage(name: String, side: CGFloat, settings: CompositionSettings) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.8, weight: settings.fontWeight.nsWeight)
        guard let configured = base.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }

    private static func renderString(_ raw: String, side: CGFloat, settings: CompositionSettings,
                                     applyTint: Bool, useEmojiFont: Bool = false) -> NSImage? {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        let maxSide = side * 0.9
        var fontSize = side * 0.8
        var attributed = attributedString(string, fontSize: fontSize, settings: settings,
                                          applyTint: applyTint, useEmojiFont: useEmojiFont)
        var bounds = attributed.size()
        // 幅か高さがはみ出す場合は、はみ出しの大きい方に合わせて縮小して収める
        // (絵文字や行間の広いフォントは高さの方が先にはみ出す)
        let overflow = max(bounds.width / maxSide, bounds.height / maxSide)
        if overflow > 1 {
            fontSize /= overflow
            attributed = attributedString(string, fontSize: fontSize, settings: settings,
                                          applyTint: applyTint, useEmojiFont: useEmojiFont)
            bounds = attributed.size()
        }

        return BitmapCanvas.draw(size: CGSize(width: side, height: side)) { _ in
            let origin = CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2)
            attributed.draw(at: origin)
        }
    }

    private static func attributedString(_ string: String, fontSize: CGFloat, settings: CompositionSettings,
                                         applyTint: Bool, useEmojiFont: Bool = false) -> NSAttributedString {
        let font = useEmojiFont ? emojiFont(size: fontSize) : makeFont(size: fontSize, settings: settings)
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if applyTint { attrs[.foregroundColor] = settings.tintColor.nsColor }
        return NSAttributedString(string: string, attributes: attrs)
    }

    /// 絵文字はカラーで描くため専用フォントを使う。見つからない場合のみシステムフォントに退避。
    private static func emojiFont(size: CGFloat) -> NSFont {
        NSFont(name: "Apple Color Emoji", size: size) ?? NSFont.systemFont(ofSize: size)
    }

    /// fontName が nil ならシステムフォントの rounded デザイン
    static func makeFont(size: CGFloat, settings: CompositionSettings) -> NSFont {
        if let name = settings.fontName, let custom = NSFont(name: name, size: size) {
            return custom
        }
        let system = NSFont.systemFont(ofSize: size, weight: settings.fontWeight.nsWeight)
        if let rounded = system.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: size) {
            return font
        }
        return system
    }
}
