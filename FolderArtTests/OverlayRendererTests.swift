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
        // 記号・絵文字・文字は常に正方形になる。画像は元のアスペクト比のまま (別テストで検証) なので
        // ここでは含めない。
        for overlay in [Overlay.symbol(name: "star.fill"), .emoji("🎵"), .text("2026")] {
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

    /// 画像は配置 (中央/バッジ) や切り抜き有無に関わらず、正方形に押し込めず元のアスペクト比を
    /// 保ったまま長辺を side に合わせて縮小するだけにする (round6)。ここで正方形にしてしまうと、
    /// 中央 fit/バッジでは余白ができ、切り抜き+中央では IconComposer 側の verticalOffset による
    /// パンではみ出し部分が失われてフォルダーの地色が透明な帯として抜けてしまう (1.0.1 の巻き戻し)
    func testImageAlwaysPreservesAspectRegardlessOfModeOrClip() throws {
        // 300x100 の横長画像 → side=512 なら長辺(300)基準で 512x171 になる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        let modes: [(IconPosition, Bool)] = [
            (.center, true), (.center, false), (.badge, true), (.badge, false),
        ]
        for (position, clip) in modes {
            var settings = CompositionSettings()
            settings.position = position
            settings.clipToFolderShape = clip
            let image = try XCTUnwrap(
                OverlayRenderer.render(.image(assetID: id), settings: settings, side: 512, assets: assets),
                "position=\(position) clip=\(clip)")
            let size = TestSupport.pixelSize(of: image)
            XCTAssertEqual(size.width, 512, accuracy: 1, "position=\(position) clip=\(clip)")
            XCTAssertEqual(size.height, 171, accuracy: 1, "position=\(position) clip=\(clip)")
        }
    }

    /// 縦長画像でも同様に、正方形にせず長辺基準でアスペクトを保ったまま縮小する
    func testPortraitImagePreservesAspect() throws {
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
}
