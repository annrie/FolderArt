import XCTest
import AppKit
@testable import FolderArt

final class IconComposerTests: XCTestCase {

    func testCenterCalculationIsMiddle() {
        // clipToFolderShape=false のときはスケールが適用される
        let settings = CompositionSettings(position: .center, scale: 0.5, opacity: 1.0,
                                           clipToFolderShape: false)
        let imageSize = CGSize(width: 100, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        let expectedSide = containerSize.width * settings.scale  // 256
        XCTAssertEqual(rect.width, expectedSide, accuracy: 0.1)
        XCTAssertEqual(rect.height, expectedSide, accuracy: 0.1)
        // 中央配置のX座標: (512 - 256) / 2 = 128
        XCTAssertEqual(rect.origin.x, (containerSize.width - expectedSide) / 2, accuracy: 0.1)
        XCTAssertEqual(rect.origin.y, (containerSize.height - expectedSide) / 2, accuracy: 0.1)
    }

    func testCenterWithClipUsesAspectFill() {
        // clipToFolderShape=true のとき AspectFill でコンテナを埋める
        let settings = CompositionSettings(position: .center, scale: 0.5, opacity: 1.0,
                                           clipToFolderShape: true)
        let imageSize = CGSize(width: 200, height: 100)  // 2:1 横長
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        // AspectFill: 幅方向でコンテナを満たす（2:1 画像→横がはみ出す）
        XCTAssertGreaterThanOrEqual(rect.width, containerSize.width - 0.1)
        // アスペクト比は保持
        XCTAssertEqual(rect.width / rect.height, 2.0, accuracy: 0.01)
    }

    func testBadgeCalculationIsBottomRight() {
        let settings = CompositionSettings(position: .badge, scale: 0.6, opacity: 1.0)
        let imageSize = CGSize(width: 100, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        // バッジは右下 → x + width が containerSize.width 付近
        XCTAssertGreaterThan(rect.origin.x, containerSize.width / 2)
        // y は下部（NSRect は bottom-left origin）
        XCTAssertLessThan(rect.origin.y, containerSize.height / 2)
    }

    /// 画像はもう正方形に押し込められず元のアスペクト比のまま渡ってくる (round6)。
    /// バッジ配置ではその画像が右下にぴったり収まる (パディング分だけ内側) ことを確認する
    func testBadgePlacementFlushToBottomRightWithAspectPreservingImage() {
        let settings = CompositionSettings(position: .badge, opacity: 1.0)
        let imageSize = CGSize(width: 300, height: 100)  // OverlayRenderer が渡す非正方形画像を模す
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        let padding: CGFloat = 20
        XCTAssertEqual(rect.maxX, containerSize.width - padding, accuracy: 0.1)
        XCTAssertEqual(rect.minY, padding, accuracy: 0.1)
        XCTAssertEqual(rect.width / rect.height, 3.0, accuracy: 0.01)
    }

    func testAspectRatioPreserved() {
        let settings = CompositionSettings(position: .center, scale: 0.8, opacity: 1.0)
        // 2:1 の横長画像
        let imageSize = CGSize(width: 200, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        let aspectRatio = rect.width / rect.height
        XCTAssertEqual(aspectRatio, 2.0, accuracy: 0.01)
    }

    func testComposeReturnsNonNilImage() {
        let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .center, scale: 0.6, opacity: 0.9)
        let result = IconComposer.compose(overlay: overlay, settings: settings)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, IconComposer.iconSize)
        XCTAssertEqual(TestSupport.pixelSize(of: result!), IconComposer.iconSize)
    }

    /// OverlayRenderer が切り抜き+中央配置のときに正方形へ切り抜かず縦長のまま長辺基準で
    /// 縮小して渡すようになった (round5)。ここではその出力を模した縦長オーバーレイを
    /// verticalOffset で上にパンして合成し、下端まできちんと覆われる (途中でフォルダーの
    /// 地色が透明な帯として見えてしまわない) ことを確認する
    func testClippedCenterPortraitOverlayCoversFolderBodyWhenPannedUp() throws {
        var settings = CompositionSettings(position: .center, opacity: 1.0, clipToFolderShape: true)
        settings.verticalOffset = 0.2
        // OverlayRenderer.render が 100x300 の画像を side=512 で長辺基準に縮小すると
        // およそ 171x512 になる (round5 の OverlayRendererTests と対応)
        let overlay = TestSupport.makeSolidImage(size: CGSize(width: 171, height: 512), color: .red)

        let composed = try XCTUnwrap(IconComposer.compose(overlay: overlay, settings: settings))
        let rep = TestSupport.bitmap(of: composed)

        for y in [200, 450] {
            let color = try XCTUnwrap(TestSupport.srgbColor(of: rep, x: 256, y: y), "y=\(y)")
            XCTAssertGreaterThan(color.alphaComponent, 0.5, "y=\(y) はフォルダー本体の内側のはず")
            XCTAssertGreaterThan(color.redComponent, 0.5, "y=\(y) が赤くない (フォルダーの地色が透けている)")
            XCTAssertLessThan(color.greenComponent, 0.3, "y=\(y) が赤くない (フォルダーの地色が透けている)")
        }
    }

    func testComposeIsDeterministicAndDoesNotStack() {
        // 標準フォルダアイコンを土台にするので、同じ入力なら何度合成しても同じ結果
        let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .badge, scale: 0.8, opacity: 1.0, clipToFolderShape: false)
        let a = IconComposer.compose(overlay: overlay, settings: settings)!
        let b = IconComposer.compose(overlay: overlay, settings: settings)!
        XCTAssertEqual(TestSupport.pngData(a), TestSupport.pngData(b))
        XCTAssertTrue(TestSupport.contains(color: .red, in: a))
    }
}
