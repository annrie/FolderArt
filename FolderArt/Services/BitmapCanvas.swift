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
              // 描く前に sRGB として扱わせる。sRGB の色を calibratedRGB のビットマップに
              // 描くと変換がかかって色がずれるため
              let srgb = rep.retagging(with: .sRGB),
              let ctx = NSGraphicsContext(bitmapImageRep: srgb)
        else { return nil }
        srgb.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        body(size)
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(srgb)
        return image
    }
}
