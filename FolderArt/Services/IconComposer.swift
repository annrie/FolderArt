import AppKit
import CoreGraphics

struct CompositionSettings: Equatable {
    var position: IconPosition = .center
    var scale: Double = 0.6      // 0.2 ... 1.0
    var opacity: Double = 0.9    // 0.1 ... 1.0
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

        // カスタム画像を不透明度付きで描画
        customImage.draw(
            in: customRect,
            from: NSRect(origin: .zero, size: customImage.size),
            operation: .sourceOver,
            fraction: settings.opacity
        )

        let result = NSImage(size: size)
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
            let maxDimension = min(containerSize.width, containerSize.height) * settings.scale
            if aspectRatio >= 1 {
                customWidth  = maxDimension
                customHeight = maxDimension / aspectRatio
            } else {
                customHeight = maxDimension
                customWidth  = maxDimension * aspectRatio
            }
            let x = (containerSize.width  - customWidth)  / 2
            let y = (containerSize.height - customHeight) / 2
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
            let y = padding
            return NSRect(x: x, y: y, width: customWidth, height: customHeight)
        }
    }
}
