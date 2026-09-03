import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class OverlayStateTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("OverlayStateTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testOverlayFollowsActiveTab() {
        let state = OverlayState(assets: assets)
        XCTAssertNil(state.overlay)
        state.activeTab = .text; state.text = "26"
        XCTAssertEqual(state.overlay, .text("26"))
        state.activeTab = .emoji
        XCTAssertNil(state.overlay)               // 絵文字は未入力
        state.emoji = "🎵"
        XCTAssertEqual(state.overlay, .emoji("🎵"))
        state.activeTab = .symbol; state.symbolName = "star.fill"
        XCTAssertEqual(state.overlay, .symbol(name: "star.fill"))
        state.activeTab = .text                   // 入力はタブごとに保持される
        XCTAssertEqual(state.overlay, .text("26"))
    }

    func testPreviewIsNilWithoutInputAndGeneratedWithInput() {
        let state = OverlayState(assets: assets)
        state.updatePreviewNow()
        XCTAssertNil(state.previewImage)
        XCTAssertFalse(state.canApply)

        state.activeTab = .symbol; state.symbolName = "star.fill"
        state.updatePreviewNow()
        XCTAssertNotNil(state.overlayImage)
        XCTAssertNotNil(state.previewImage)
        XCTAssertEqual(state.previewImage?.size, IconComposer.iconSize)
        XCTAssertTrue(state.canApply)
    }

    func testDebouncedPreviewUpdatesAfterChange() async {
        let state = OverlayState(assets: assets, debounce: 0.05)
        state.activeTab = .text
        state.text = "A"
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(state.previewImage)
    }

    func testSelectImageCopiesIntoAssetStoreAndSwitchesTab() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("src.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 20, height: 20), color: .green)).write(to: src)

        let state = OverlayState(assets: assets)
        state.activeTab = .text
        try state.selectImage(url: src)
        XCTAssertEqual(state.activeTab, .image)
        let id = try XCTUnwrap(state.imageAssetID)
        XCTAssertNotNil(assets.image(for: id))
        XCTAssertEqual(state.overlay, .image(assetID: id))
    }

    func testRestoreFromPresetSetsTabInputAndSettings() {
        let state = OverlayState(assets: assets)
        var settings = CompositionSettings()
        settings.position = .badge
        settings.tintColor = .black
        state.restore(overlay: .emoji("📷"), settings: settings)
        XCTAssertEqual(state.activeTab, .emoji)
        XCTAssertEqual(state.emoji, "📷")
        XCTAssertEqual(state.settings, settings)
    }

    /// 文字は切り抜き ON + 中央でもサイズが効く (敷き詰めなら 0.3 と 0.9 で同じ絵になってしまう)
    func testGlyphPreviewChangesWithScaleEvenWhenClipped() {
        let state = OverlayState(assets: assets)
        state.activeTab = .text
        state.text = "I"
        state.settings.clipToFolderShape = true
        state.settings.position = .center
        state.settings.scale = 0.3
        state.updatePreviewNow()
        let small = TestSupport.pngData(state.previewImage!)
        state.settings.scale = 0.9
        state.updatePreviewNow()
        let large = TestSupport.pngData(state.previewImage!)
        XCTAssertNotEqual(small, large)
    }
}
