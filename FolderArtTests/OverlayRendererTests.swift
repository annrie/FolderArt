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

    func testImageKeepsAspectInsideSquare() throws {
        // 300x100 の赤い画像 → 256x256 の中で上下に透明帯ができる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        let image = render(.image(assetID: id))!
        let rep = TestSupport.bitmap(of: image)
        XCTAssertEqual(rep.colorAt(x: 128, y: 128)!.alphaComponent, 1.0, accuracy: 0.01) // 中央は不透明
        XCTAssertEqual(rep.colorAt(x: 128, y: 4)!.alphaComponent, 0.0, accuracy: 0.01)   // 上端は透明
    }
}
