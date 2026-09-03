import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum IconComposer {
    static let iconSize = CGSize(width: 512, height: 512)

    /// 合成の土台。加工済みフォルダへの再適用で重ね塗りにならないよう、常に標準アイコンを使う
    static let standardFolderIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = iconSize
        return icon
    }()

    /// 土台アイコンにオーバーレイ画像 (OverlayRenderer の出力) を合成して返す
    /// - Parameter fillsWhenClipped: 切り抜き ON + 中央のとき、フォルダ全体に敷き詰める (画像) か、
    ///   サイズ指定どおりに置いてはみ出しだけ切り抜く (記号・絵文字・文字) か。
    static func compose(
        overlay overlayImage: NSImage,
        settings: CompositionSettings,
        base: NSImage = standardFolderIcon,
        fillsWhenClipped: Bool
    ) -> NSImage? {
        let size = iconSize
        let overlayRect = calculateRect(for: overlayImage.size, in: size, settings: settings,
                                        fillsWhenClipped: fillsWhenClipped)

        return BitmapCanvas.draw(size: size) { _ in
            base.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: base.size),
                      operation: .sourceOver, fraction: 1)

            if settings.clipToFolderShape {
                if let clipped = makeClipped(overlayImage: overlayImage, overlayRect: overlayRect,
                                             base: base, containerSize: size, opacity: settings.opacity) {
                    clipped.draw(in: NSRect(origin: .zero, size: size))
                }
            } else {
                overlayImage.draw(in: overlayRect,
                                  from: NSRect(origin: .zero, size: overlayImage.size),
                                  operation: .sourceOver, fraction: settings.opacity)
            }
        }
    }

    /// オーバーレイを土台アイコンのアルファ形状で切り抜く (destinationIn)
    private static func makeClipped(
        overlayImage: NSImage, overlayRect: NSRect, base: NSImage,
        containerSize: CGSize, opacity: Double
    ) -> NSImage? {
        BitmapCanvas.draw(size: containerSize) { _ in
            overlayImage.draw(in: overlayRect,
                              from: NSRect(origin: .zero, size: overlayImage.size),
                              operation: .sourceOver, fraction: opacity)
            base.draw(in: NSRect(origin: .zero, size: containerSize),
                      from: NSRect(origin: .zero, size: base.size),
                      operation: .destinationIn, fraction: 1.0)
        }
    }

    /// 配置設定に基づいてオーバーレイの描画 Rect を計算する (現行と同一)
    static func calculateRect(
        for imageSize: CGSize,
        in containerSize: CGSize,
        settings: CompositionSettings,
        fillsWhenClipped: Bool
    ) -> NSRect {
        let aspectRatio = imageSize.width > 0 ? imageSize.width / imageSize.height : 1.0
        let customWidth: CGFloat
        let customHeight: CGFloat

        switch settings.position {
        case .center:
            if settings.clipToFolderShape && fillsWhenClipped {
                let containerAspect = containerSize.width / containerSize.height
                if aspectRatio >= containerAspect {
                    customHeight = containerSize.height
                    customWidth  = customHeight * aspectRatio
                } else {
                    customWidth  = containerSize.width
                    customHeight = customWidth / aspectRatio
                }
            } else {
                let maxDimension = min(containerSize.width, containerSize.height) * settings.scale
                if aspectRatio >= 1 {
                    customWidth  = maxDimension
                    customHeight = maxDimension / aspectRatio
                } else {
                    customHeight = maxDimension
                    customWidth  = maxDimension * aspectRatio
                }
            }
            let x = (containerSize.width  - customWidth)  / 2
            let yBase = (containerSize.height - customHeight) / 2
            let yShift = containerSize.height * settings.verticalOffset
            return NSRect(x: x, y: yBase + yShift, width: customWidth, height: customHeight)

        case .badge:
            let badgeMax = min(containerSize.width, containerSize.height) * settings.scale * 0.45
            if aspectRatio >= 1 {
                customWidth  = badgeMax
                customHeight = badgeMax / aspectRatio
            } else {
                customHeight = badgeMax
                customWidth  = badgeMax * aspectRatio
            }
            let padding: CGFloat = 20
            let x = containerSize.width  - customWidth  - padding
            let yShift = containerSize.height * settings.verticalOffset
            return NSRect(x: x, y: padding + yShift, width: customWidth, height: customHeight)
        }
    }
}
