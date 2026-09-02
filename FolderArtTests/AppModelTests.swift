import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        model = AppModel(
            history: HistoryStore(storageURL: root.appendingPathComponent("history.json")),
            presets: PresetStore(storageURL: root.appendingPathComponent("presets.json")),
            assets: AssetStore(directory: root.appendingPathComponent("assets")))
    }
    override func tearDown() async throws {
        for t in model.history.tasks { NSWorkspace.shared.setIcon(nil, forFile: t.folderPath, options: []) }
        try? FileManager.default.removeItem(at: root)
    }

    func testCanApplyNeedsFoldersAndOverlay() throws {
        XCTAssertFalse(model.canApply)
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        model.addFolders([a])
        XCTAssertFalse(model.canApply)
        model.overlay.activeTab = .text
        model.overlay.text = "x"
        model.overlay.updatePreviewNow()
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.applyButtonTitle, String(localized: "1 フォルダに適用"))
        model.folders.selectedIDs = [a.standardizedFileURL]
        XCTAssertEqual(model.applyButtonTitle, String(localized: "選択した 1 フォルダに適用"))
    }

    /// overlay (メタデータ) はデバウンス無しで常に最新値を返すため、履歴の overlay フィールドだけでは
    /// 「古い画像で適用してしまう」バグを検出できない。また apply() 完了後の overlayImage は
    /// 実行中に自然にデバウンスが追いつくため、これも検出に使えない。
    /// そこで実際にフォルダーへ書き込まれたアイコン (書いた時点のまま変わらない) の色を見る。
    func testApplyRendersCurrentInputEvenBeforeDebounce() async throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        model.addFolders([a])

        let redID = try model.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        let blueID = try model.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .blue))

        model.overlay.activeTab = .image
        model.overlay.imageAssetID = redID
        model.overlay.updatePreviewNow()   // 赤を同期描画済みにしておく
        model.overlay.imageAssetID = blueID  // デバウンス前に適用 (青の反映はまだ)

        await model.apply()

        let appliedIcon = NSWorkspace.shared.icon(forFile: a.path)
        XCTAssertTrue(TestSupport.contains(color: .blue, in: appliedIcon))
        XCTAssertFalse(TestSupport.contains(color: .red, in: appliedIcon))
        XCTAssertEqual(model.history.task(forFolderPath: a.standardizedFileURL.path)?.overlay, .image(assetID: blueID))
        XCTAssertNil(model.errorMessage)
    }

    func testDroppedURLsAreRouted() throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let png = root.appendingPathComponent("pic.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)).write(to: png)
        model.overlay.activeTab = .text
        model.handleDroppedURLs([a, png])
        XCTAssertEqual(model.folders.folders.count, 1)
        XCTAssertEqual(model.overlay.activeTab, .image)
        XCTAssertNotNil(model.overlay.imageAssetID)
    }

    func testReapIsSkippedWhenAStoreFailedToLoad() throws {
        let broken = root.appendingPathComponent("broken.json")
        try "x".data(using: .utf8)!.write(to: broken)
        let m = AppModel(history: HistoryStore(storageURL: broken),
                         presets: PresetStore(storageURL: root.appendingPathComponent("p.json")),
                         assets: model.assets)
        let orphan = try m.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .blue))
        m.reapAssets()
        XCTAssertTrue(m.assets.allIDs().contains(orphan))
        XCTAssertNotNil(m.errorMessage)
    }

    func testRestoreFromHistoryTaskSetsOverlayAndFolder() throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        var settings = CompositionSettings(); settings.position = .badge
        // ブックマークがある行はブックマーク経由で解決する (再起動後の App Sandbox 対策)
        let bookmark = try BookmarkManager.createBookmark(for: a)
        let task = IconTask(folderPath: a.path, bookmarkData: bookmark, backupPath: nil,
                            overlay: .text("26"), settings: settings)
        model.restore(from: task)
        XCTAssertEqual(model.overlay.activeTab, .text)
        XCTAssertEqual(model.overlay.text, "26")
        XCTAssertEqual(model.overlay.settings.position, .badge)
        XCTAssertEqual(model.folders.folders.count, 1)
        XCTAssertEqual(model.folders.folders.first, a.standardizedFileURL)
        model.restore(from: IconTask(folderPath: a.path, bookmarkData: Data(), backupPath: nil,
                                     overlay: .legacyImage(name: "x"), settings: CompositionSettings()))
        XCTAssertEqual(model.overlay.text, "26")   // 旧形式は無視
    }

    func testSavePresetAndReapKeepsReferencedAssets() throws {
        let png = root.appendingPathComponent("pic.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)).write(to: png)
        try model.overlay.selectImage(url: png)
        let used = model.overlay.imageAssetID!
        let orphan = try model.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .blue))
        model.saveCurrentAsPreset()
        XCTAssertEqual(model.presets.presets.count, 1)
        model.reapAssets()
        XCTAssertEqual(model.assets.allIDs(), [used])
        XCTAssertFalse(model.assets.allIDs().contains(orphan))
    }
}
