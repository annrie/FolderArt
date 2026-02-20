import AppKit
import CoreGraphics

struct CompositionSettings: Equatable {
    var position: IconPosition = .center
    var scale: Double = 0.6              // 0.2 ... 1.0
    var opacity: Double = 0.9            // 0.1 ... 1.0
    var verticalOffset: Double = 0.0     // -0.4 ... 0.4 (上:正, 下:負)
    var clipToFolderShape: Bool = true   // フォルダー形状に切り抜く
}

class IconComposer {
    static let iconSize = CGSize(width: 512, height: 512)

    /// フォルダーアイコンにカスタム画像を合成して返す
    static func compose(
        folderPath: String,
        customImage: NSImage,
        settings: CompositionSettings
    ) -> NSImage? {
        let size = iconSize

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        NSGraphicsContext.current = ctx

        // ベースのフォルダーアイコンを描画
        let folderIcon = NSWorkspace.shared.icon(forFile: folderPath)
        folderIcon.draw(in: NSRect(origin: .zero, size: size))

        // カスタム画像の描画範囲を計算
        let customRect = calculateRect(
            for: customImage.size,
            in: size,
            settings: settings
        )

        // カスタム画像を合成（切り抜きモードで分岐）
        if settings.clipToFolderShape {
            // フォルダー形状に切り抜いた画像を別キャンバスで生成して合成
            if let clipped = makeClipped(
                customImage: customImage,
                customRect: customRect,
                folderIcon: folderIcon,
                containerSize: size,
                opacity: settings.opacity
            ) {
                clipped.draw(in: NSRect(origin: .zero, size: size))
            }
        } else {
            // フルイメージ: そのままオーバーレイ
            customImage.draw(
                in: customRect,
                from: NSRect(origin: .zero, size: customImage.size),
                operation: .sourceOver,
                fraction: settings.opacity
            )
        }

        let result = NSImage(size: size)
        result.addRepresentation(bitmapRep)
        return result
    }

    /// カスタム画像をフォルダーアイコンのアルファ形状で切り抜いた NSImage を返す
    ///
    /// アルゴリズム:
    ///   1. 独立キャンバスにカスタム画像を描画
    ///   2. フォルダーアイコンを .destinationIn で重ねる
    ///      → destinationIn: result = customImage × folderIcon.alpha
    ///      → フォルダーが不透明な領域だけカスタム画像が残る
    private static func makeClipped(
        customImage: NSImage,
        customRect: NSRect,
        folderIcon: NSImage,
        containerSize: CGSize,
        opacity: Double
    ) -> NSImage? {
        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(containerSize.width),
            pixelsHigh: Int(containerSize.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        NSGraphicsContext.current = ctx

        customImage.draw(
            in: customRect,
            from: NSRect(origin: .zero, size: customImage.size),
            operation: .sourceOver,
            fraction: opacity
        )
        folderIcon.draw(
            in: NSRect(origin: .zero, size: containerSize),
            from: NSRect(origin: .zero, size: folderIcon.size),
            operation: .destinationIn,
            fraction: 1.0
        )

        let result = NSImage(size: containerSize)
        result.addRepresentation(bitmapRep)
        return result
    }

    /// 配置設定に基づいてカスタム画像の描画 Rect を計算する
    static func calculateRect(
        for imageSize: CGSize,
        in containerSize: CGSize,
        settings: CompositionSettings
    ) -> NSRect {
        let aspectRatio = imageSize.width > 0 ? imageSize.width / imageSize.height : 1.0
        let customWidth: CGFloat
        let customHeight: CGFloat

        switch settings.position {
        case .center:
            if settings.clipToFolderShape {
                // AspectFill: フォルダー全体を埋めるように拡大し、形状でクリップ
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
            // verticalOffset: 正=上, 負=下 (NSRect は bottom-left origin)
            let yShift = containerSize.height * settings.verticalOffset
            let y = yBase + yShift
            return NSRect(x: x, y: y, width: customWidth, height: customHeight)

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
            let yBase = padding
            let yShift = containerSize.height * settings.verticalOffset
            let y = yBase + yShift
            return NSRect(x: x, y: y, width: customWidth, height: customHeight)
        }
    }
}
