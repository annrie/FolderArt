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

    /// 再適用のたびにセキュリティスコープを開き直さない。リストから消えたら閉じる
    func testSecurityScopeIsOpenedOnceAndClosedWithTheList() throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let task = IconTask(folderPath: a.path,
                            bookmarkData: try BookmarkManager.createBookmark(for: a),
                            backupPath: nil, overlay: .text("1"), settings: CompositionSettings())

        model.restore(from: task)
        model.restore(from: task)
        XCTAssertEqual(model.scopedURLCount, 1)

        model.folders.removeAll()
        XCTAssertEqual(model.scopedURLCount, 0)
    }

    /// 適用中は addFolders / handleDroppedURLs でリストが増えない (ウィンドウ全体・リストのドロップ両方がこれを通る)
    func testFolderMutationsAreIgnoredWhileApplying() throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)

        model.isApplying = true
        model.addFolders([a])
        model.handleDroppedURLs([a])
        XCTAssertTrue(model.folders.folders.isEmpty)

        model.isApplying = false
        model.addFolders([a])
        XCTAssertEqual(model.folders.folders.count, 1)
    }

    /// 適用中は履歴からの reset(task:) が効かない (二重操作を防ぐ)。resetTargets() は
    /// フォルダを直接触らないここでは検証しないが、同じガードで守られている
    func testResetTaskIsIgnoredWhileApplying() async throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        model.addFolders([a])
        model.overlay.activeTab = .text
        model.overlay.text = "x"
        model.overlay.updatePreviewNow()
        await model.apply()

        let task = try XCTUnwrap(model.history.task(forFolderPath: a.standardizedFileURL.path))
        let iconFile = a.appendingPathComponent("Icon\r")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconFile.path))

        model.isApplying = true
        model.reset(task: task)

        XCTAssertTrue(FileManager.default.fileExists(atPath: iconFile.path))
        XCTAssertNotNil(model.history.task(forFolderPath: a.standardizedFileURL.path))

        model.isApplying = false
    }

    /// ブックマークが無く生パスも存在しないフォルダは FolderSelection.add で黙って弾かれるので、
    /// restore はそれをエラーとして表面化し、オーバーレイは変更しない
    /// ブックマークは解決できたがリストに追加できない (フォルダが通常ファイルに置き換わった) 場合、
    /// 開いたばかりのセキュリティスコープを残さない
    func testRestoreReleasesScopeWhenFolderCannotBeAdded() throws {
        // ブックマークが通常ファイルを指している (フォルダが差し替わった) と、解決はできるが追加は拒否される
        let a = root.appendingPathComponent("A")
        try "file".data(using: .utf8)!.write(to: a)
        let bookmark = try BookmarkManager.createBookmark(for: a)
        let task = IconTask(folderPath: a.path, bookmarkData: bookmark, backupPath: nil,
                            overlay: .text("7"), settings: CompositionSettings())

        model.restore(from: task)

        XCTAssertTrue(model.folders.folders.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.scopedURLCount, 0)
    }

    /// 適用中に apply() が再度呼ばれても何もしない (連打で 2 バッチが交錯しない)
    func testApplyIsIgnoredWhileAnotherApplyIsRunning() async throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        model.addFolders([a])
        model.overlay.activeTab = .text
        model.overlay.text = "x"
        model.overlay.updatePreviewNow()

        model.isApplying = true          // 先行バッチが走っている状態を模す
        await model.apply()
        XCTAssertTrue(model.history.tasks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))

        model.isApplying = false
        await model.apply()
        XCTAssertEqual(model.history.tasks.count, 1)
    }

    func testRestoreShowsErrorWhenBookmarkFailsToResolve() throws {
        let missing = root.appendingPathComponent("MissingFolder")   // 作成しない
        let task = IconTask(folderPath: missing.path, bookmarkData: Data(), backupPath: nil,
                            overlay: .text("42"), settings: CompositionSettings())

        model.restore(from: task)

        XCTAssertTrue(model.folders.folders.isEmpty)
        XCTAssertNotNil(model.errorMessage)
        XCTAssertEqual(model.overlay.text, "")
    }

    /// 適用中はお気に入りの削除も参照カウントの回収も止める (二重操作・回収レースの防止)。
    /// 適用が終わったら通常どおり回収できる。
    func testPresetMutationsAndReapAreIgnoredWhileApplying() throws {
        let png = root.appendingPathComponent("pic.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)).write(to: png)
        try model.overlay.selectImage(url: png)
        model.saveCurrentAsPreset()
        let preset = try XCTUnwrap(model.presets.presets.first)

        let orphan = try model.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .blue))

        model.isApplying = true
        model.removePreset(preset)
        model.reapAssets()
        XCTAssertEqual(model.presets.presets.count, 1, "適用中は削除できない")
        XCTAssertTrue(model.assets.allIDs().contains(orphan), "適用中は回収できない")

        model.isApplying = false
        model.reapAssets()
        XCTAssertFalse(model.assets.allIDs().contains(orphan), "適用が終われば回収される")
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
