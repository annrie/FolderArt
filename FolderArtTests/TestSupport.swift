import AppKit
@testable import FolderArt

enum TestSupport {
    /// 単色のビットマップ画像 (pixel == point)
    static func makeSolidImage(size: CGSize, color: NSColor) -> NSImage {
        BitmapCanvas.draw(size: size) { _ in
            color.setFill()
            NSRect(origin: .zero, size: size).fill()
        }!
    }

    static func bitmap(of image: NSImage) -> NSBitmapImageRep {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first { return rep }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
    }

    /// 最初のビットマップ表現のピクセル寸法
    static func pixelSize(of image: NSImage) -> CGSize {
        let rep = bitmap(of: image)
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// 1 ピクセルを sRGB で読む。
    /// `NSBitmapImageRep.colorAt` は colorSpaceName しか見ず、retagging した rep の色を
    /// 取り違えるので、生のピクセル値を rep の実際の colorSpace で解釈する。
    static func srgbColor(of rep: NSBitmapImageRep, x: Int, y: Int) -> NSColor? {
        var pixel = [Int](repeating: 0, count: 5)
        rep.getPixel(&pixel, atX: x, y: y)
        let components = (0..<4).map { CGFloat(pixel[$0]) / 255.0 }
        return NSColor(colorSpace: rep.colorSpace, components: components, count: 4)
            .usingColorSpace(.sRGB)
    }

    static func srgbColor(of image: NSImage, x: Int, y: Int) -> NSColor? {
        srgbColor(of: bitmap(of: image), x: x, y: y)
    }

    /// 画像中に指定色 (sRGB, 許容誤差付き) のピクセルがあるか。4px 刻みで走査。
    static func contains(color target: NSColor, in image: NSImage, tolerance: CGFloat = 0.08) -> Bool {
        let rep = bitmap(of: image)
        let t = target.usingColorSpace(.sRGB)!
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let c = srgbColor(of: rep, x: x, y: y), c.alphaComponent > 0.9 else { continue }
                if abs(c.redComponent - t.redComponent) < tolerance,
                   abs(c.greenComponent - t.greenComponent) < tolerance,
                   abs(c.blueComponent - t.blueComponent) < tolerance { return true }
            }
        }
        return false
    }

    static func pngData(_ image: NSImage) -> Data {
        bitmap(of: image).representation(using: .png, properties: [:])!
    }
}
