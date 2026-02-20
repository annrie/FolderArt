import XCTest
import AppKit
@testable import FolderArt

final class IconComposerTests: XCTestCase {

    private func makeTestImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

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

    func testComposeReturnsNonNilImage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderArtIconTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customImage = makeTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .center, scale: 0.6, opacity: 0.9)

        let result = IconComposer.compose(
            folderPath: tempDir.path,
            customImage: customImage,
            settings: settings
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, IconComposer.iconSize)
    }
}
