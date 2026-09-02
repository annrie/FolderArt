import AppKit

/// 透明な RGBA ビットマップに描画して NSImage を返す共通ヘルパ。
/// 出力の pixel 寸法は size と一致する (Retina 倍率の影響を受けない)。
enum BitmapCanvas {
    static func draw(size: CGSize, _ body: (CGSize) -> Void) -> NSImage? {
        guard size.width >= 1, size.height >= 1,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width.rounded()),
                pixelsHigh: Int(size.height.rounded()),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        body(size)
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
