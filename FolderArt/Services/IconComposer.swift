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

    /// フォルダアイコンの「本体」(蓋を除く) の中心が正方形の中央からどれだけ下にあるか (アイコンの高さに対する比、下が正)。
    /// 不透明 (alpha > 0.5) な画素が行の最大幅の 90% 以上ある行を本体とみなす (蓋は幅が狭い)。不透明な行が無ければ nil。
    /// CompositionSettings.verticalOffset の既定値はこの値の符号を反転したもの (macOS 15.7 で 0.040)
    static func folderBodyCenterOffset(of image: NSImage, side: Int = 512) -> Double? {
        guard side > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // 行ごとの不透明な画素の数 (NSBitmapImageRep の y は上から)
        var widths: [Int] = []
        widths.reserveCapacity(side)
        for y in 0..<side {
            var n = 0
            for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { n += 1 }
            widths.append(n)
        }
        guard let maxWidth = widths.max(), maxWidth > 0 else { return nil }
        let threshold = Int((Double(maxWidth) * 0.9).rounded(.up))
        let bodyRows = widths.enumerated().filter { $0.element >= threshold }.map(\.offset)
        guard let top = bodyRows.first, let bottom = bodyRows.last else { return nil }
        let center = Double(top + bottom) / 2 + 0.5   // 画素の中心
        return (center - Double(side) / 2) / Double(side)
    }

    /// 土台アイコンにオーバーレイ画像 (OverlayRenderer の出力) を合成して返す
    /// - Parameter fillsWhenClipped: 切り抜き ON + 中央のとき、フォルダ全体に敷き詰める (画像) か、
    ///   サイズ指定どおりに置いてはみ出しだけ切り抜く (記号・絵文字・文字) か。敷き詰めるときは上下位置が
    ///   キャンバスを覆い切れる範囲にクランプされるので、正方形画像では既定の上下位置があっても動かない。
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

    /// 配置設定に基づいてオーバーレイの描画 Rect を計算する (現行と同一)。
    /// 敷き詰め (clipToFolderShape && fillsWhenClipped) では、上下位置 (verticalOffset) はキャンバスを
    /// 縦に覆い切れる範囲 (余白 = はみ出し高さ / 2) にクランプされる。正方形画像は余白 0 なので動かない
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
            var yShift = containerSize.height * settings.verticalOffset
            if settings.clipToFolderShape && fillsWhenClipped {
                // 敷き詰めではキャンバスを縦に覆い切る範囲でだけ動かす (縦長画像のパン)。正方形なら余白 0 で動かない
                let slack = max(0, (customHeight - containerSize.height) / 2)
                yShift = min(max(yShift, -slack), slack)
            }
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
