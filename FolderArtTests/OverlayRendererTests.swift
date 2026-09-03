import XCTest
import AppKit
@testable import FolderArt

final class OverlayRendererTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("RendererTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func render(_ overlay: Overlay, settings: CompositionSettings = CompositionSettings()) -> NSImage? {
        OverlayRenderer.render(overlay, settings: settings, side: 256, assets: assets)
    }

    func testEachKindRendersSquare() throws {
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        for overlay in [Overlay.image(assetID: id), .symbol(name: "star.fill"), .emoji("🎵"), .text("2026")] {
            let image = try XCTUnwrap(render(overlay), "\(overlay)")
            XCTAssertEqual(TestSupport.pixelSize(of: image), CGSize(width: 256, height: 256), "\(overlay)")
        }
    }

    func testEmptyTextAndEmojiReturnNil() {
        XCTAssertNil(render(.text("")))
        XCTAssertNil(render(.text("   ")))
        XCTAssertNil(render(.emoji("")))
        XCTAssertNil(render(.legacyImage(name: "old.png")))
        XCTAssertNil(render(.image(assetID: UUID())))
        XCTAssertNil(render(.symbol(name: "this.symbol.does.not.exist.zzz")))
    }

    func testSymbolAndTextUseTintColor() {
        var settings = CompositionSettings()
        settings.tintColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let symbol = render(.symbol(name: "square.fill"), settings: settings)!
        XCTAssertTrue(TestSupport.contains(color: .red, in: symbol))
        let text = render(.text("I"), settings: settings)!
        XCTAssertTrue(TestSupport.contains(color: .red, in: text))
    }

    /// sRGB のまま描けているか: 指定した色がほぼそのままピクセルに出る
    func testTextTintIsWrittenAsSRGB() throws {
        var settings = CompositionSettings()
        settings.tintColor = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 1)
        let image = try XCTUnwrap(render(.text("I"), settings: settings))
        let rep = TestSupport.bitmap(of: image)

        let y = rep.pixelsHigh / 2
        var opaque: NSColor?
        for x in 0..<rep.pixelsWide {
            if let c = TestSupport.srgbColor(of: rep, x: x, y: y), c.alphaComponent > 0.99 {
                opaque = c
                break
            }
        }
        let color = try XCTUnwrap(opaque, "中央の行に不透明なピクセルがない")
        XCTAssertEqual(color.redComponent,   0.2, accuracy: 0.03)
        XCTAssertEqual(color.greenComponent, 0.4, accuracy: 0.03)
        XCTAssertEqual(color.blueComponent,  0.6, accuracy: 0.03)
    }

    func testEmojiRendersInColor() throws {
        // 🍎 で検証: Apple のデザイン上 🎵 (音符) はほぼ黒一色で彩度が低く判定に使えないため、
        // 赤/緑がはっきり出る絵文字で Apple Color Emoji フォントが使われているかを確認する
        let image = try XCTUnwrap(
            OverlayRenderer.render(.emoji("🍎"), settings: CompositionSettings(), side: 128, assets: assets))
        XCTAssertTrue(TestSupport.containsSaturatedPixel(in: image))
    }

    func testImageKeepsAspectInsideSquare() throws {
        // 300x100 の赤い画像 → 256x256 の中で上下に透明帯ができる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        let image = render(.image(assetID: id))!
        let rep = TestSupport.bitmap(of: image)
        XCTAssertEqual(rep.colorAt(x: 128, y: 128)!.alphaComponent, 1.0, accuracy: 0.01) // 中央は不透明
        XCTAssertEqual(rep.colorAt(x: 128, y: 4)!.alphaComponent, 0.0, accuracy: 0.01)   // 上端は透明
    }
}
