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
        // .image は切り抜き+中央配置だとアスペクトを保った非正方形になる (別テストで検証) ので、
        // ここでは clipToFolderShape を OFF にして「通常は正方形に収まる」ことだけを確認する
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        var settings = CompositionSettings()
        settings.clipToFolderShape = false
        for overlay in [Overlay.image(assetID: id), .symbol(name: "star.fill"), .emoji("🎵"), .text("2026")] {
            let image = try XCTUnwrap(render(overlay, settings: settings), "\(overlay)")
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
        // 300x100 の赤い画像 → clipToFolderShape が OFF のときは aspect-FIT され、
        // 256x256 の中で上下に透明帯ができる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        var settings = CompositionSettings()
        settings.clipToFolderShape = false
        let image = render(.image(assetID: id), settings: settings)!
        let rep = TestSupport.bitmap(of: image)
        XCTAssertEqual(rep.colorAt(x: 128, y: 128)!.alphaComponent, 1.0, accuracy: 0.01) // 中央は不透明
        XCTAssertEqual(rep.colorAt(x: 128, y: 4)!.alphaComponent, 0.0, accuracy: 0.01)   // 上端は透明
    }

    /// clipToFolderShape が ON (デフォルト) かつ中央配置のときは、正方形に切り抜かず元の
    /// アスペクト比を保ったまま長辺を side に合わせて縮小するだけにする (round5)。
    /// ここで正方形に切り抜くと、IconComposer 側の verticalOffset によるパンではみ出し部分が
    /// 失われ、パンした先でフォルダーの地色が透明な帯として抜けてしまう (1.0.1 の巻き戻し)
    func testImagePreservesAspectWhenClippedToFolderShapeAtCenter() throws {
        // 100x300 の縦長画像 → side=512 なら長辺(300)基準で ~171x512 になる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 100, height: 300), color: .red))
        let image = try XCTUnwrap(
            OverlayRenderer.render(.image(assetID: id), settings: CompositionSettings(), side: 512, assets: assets))
        let size = TestSupport.pixelSize(of: image)
        XCTAssertEqual(size.height, 512, accuracy: 1)
        XCTAssertEqual(size.width, 171, accuracy: 1)

        let rep = TestSupport.bitmap(of: image)
        let x = Int(size.width) / 2
        XCTAssertEqual(rep.colorAt(x: x, y: 4)!.alphaComponent, 1.0, accuracy: 0.01)                  // 下端も不透明
        XCTAssertEqual(rep.colorAt(x: x, y: 256)!.alphaComponent, 1.0, accuracy: 0.01)                // 中央も不透明
        XCTAssertEqual(rep.colorAt(x: x, y: Int(size.height) - 4)!.alphaComponent, 1.0, accuracy: 0.01) // 上端も不透明 (帯なし)
    }

    /// clipToFolderShape が OFF のときは今まで通り正方形に aspect-FIT され、
    /// はみ出さない側 (この場合は左右) に透明帯ができる
    func testImageFitsIntoSquareWithSideBandsWhenClipDisabled() throws {
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 100, height: 300), color: .red))
        var settings = CompositionSettings()
        settings.clipToFolderShape = false
        let image = try XCTUnwrap(
            OverlayRenderer.render(.image(assetID: id), settings: settings, side: 512, assets: assets))
        XCTAssertEqual(TestSupport.pixelSize(of: image), CGSize(width: 512, height: 512))

        let rep = TestSupport.bitmap(of: image)
        XCTAssertEqual(rep.colorAt(x: 256, y: 256)!.alphaComponent, 1.0, accuracy: 0.01) // 中央は不透明
        XCTAssertEqual(rep.colorAt(x: 4, y: 256)!.alphaComponent, 0.0, accuracy: 0.01)   // 左端は透明 (帯)
        XCTAssertEqual(rep.colorAt(x: 507, y: 256)!.alphaComponent, 0.0, accuracy: 0.01) // 右端は透明 (帯)
    }
}
