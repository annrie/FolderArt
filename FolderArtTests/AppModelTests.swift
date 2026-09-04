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
            assets: AssetStore(directory: root.appendingPathComponent("assets")),
            runsMaintenance: false)
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
                         assets: model.assets,
                         runsMaintenance: false)
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

    /// 提案は「選択中の行 (リスト順で最後)、無ければ最後に追加した行」の名前から作る
    func testSuggestionsFollowSelectedOrLastFolder() throws {
        let photos = root.appendingPathComponent("Photos")
        let invoices = root.appendingPathComponent("請求書")
        for d in [photos, invoices] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        model.addFolders([photos])
        XCTAssertEqual(model.suggestionSourceFolder, photos.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("📷") })

        model.addFolders([invoices])
        XCTAssertEqual(model.suggestionSourceFolder, invoices.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("🧾") })

        model.folders.selectedIDs = [photos.standardizedFileURL]
        XCTAssertEqual(model.suggestionSourceFolder, photos.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("📷") })

        model.folders.removeAll()
        XCTAssertNil(model.suggestionSourceFolder)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    /// 候補を押すとそのタブに切り替わって入力が入る。設定は変えない
    func testApplySuggestionSwitchesTabAndInput() throws {
        let before = model.overlay.settings
        model.applySuggestion(Suggestion(kind: .symbol("star.fill"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .symbol)
        XCTAssertEqual(model.overlay.symbolName, "star.fill")
        model.applySuggestion(Suggestion(kind: .emoji("🎵"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .emoji)
        XCTAssertEqual(model.overlay.emoji, "🎵")
        model.applySuggestion(Suggestion(kind: .text("2026"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .text)
        XCTAssertEqual(model.overlay.text, "2026")
        XCTAssertEqual(model.overlay.settings, before)

        var settings = CompositionSettings(); settings.position = .badge
        let preset = Preset(name: "p", overlay: .symbol(name: "heart.fill"), settings: settings)
        model.applySuggestion(Suggestion(kind: .preset(preset), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .symbol)
        XCTAssertEqual(model.overlay.settings.position, .badge)   // お気に入りだけは設定まで復元
    }

    /// お気に入りの名前がフォルダ名に含まれると、その お気に入りが提案される
    func testPresetNameInFolderNameIsSuggested() throws {
        let d = root.appendingPathComponent("旅行 2025")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try model.presets.add(name: "旅行", overlay: .emoji("✈️"), settings: CompositionSettings())
        model.addFolders([d])
        guard case .preset(let p)? = model.suggestions.first?.kind else { return XCTFail("preset first") }
        XCTAssertEqual(p.name, "旅行")
    }

    func testExportAndImportPackRoundTrip() async throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let file = root.appendingPathComponent("test.folderartpack")
        model.exportPack(to: file)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try model.presets.remove(model.presets.presets[0])
        await model.importPack(url: file)
        XCTAssertEqual(model.presets.presets.map(\.name), ["星"])
        XCTAssertEqual(model.errorMessage, String(localized: "1 件のお気に入りを追加しました。"))
    }

    func testImportPackReportsCorruptFile() async throws {
        let file = root.appendingPathComponent("bad.folderartpack")
        try "nope".data(using: .utf8)!.write(to: file)
        await model.importPack(url: file)
        XCTAssertTrue(model.presets.presets.isEmpty)
        XCTAssertEqual(model.errorMessage, PackError.corrupted.errorDescription)
    }

    func testExportIsIgnoredWhileApplying() throws {
        try model.presets.add(name: "a", overlay: .text("a"), settings: CompositionSettings())
        let file = root.appendingPathComponent("x.folderartpack")
        model.isApplying = true
        model.exportPack(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testImportIsIgnoredWhileApplying() async throws {
        let file = root.appendingPathComponent("test.folderartpack")
        try PackWriter.write([Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())],
                             assets: model.assets, appVersion: "1.3.0").write(to: file)
        model.isApplying = true
        await model.importPack(url: file)
        XCTAssertTrue(model.presets.presets.isEmpty)
    }

    /// ファイルメニューからの書き出しは常に選べるので、お気に入りが無いときは理由を伝える (黙って戻らない)
    func testExportWithNoPresetsExplains() {
        XCTAssertTrue(model.presets.presets.isEmpty)
        model.exportPack()
        XCTAssertEqual(model.errorMessage, "書き出せるお気に入りがありません。")
    }


    func testApplySuggestionIsIgnoredWhileApplying() {
        model.overlay.activeTab = .text
        model.overlay.text = "before"
        model.isApplying = true
        model.applySuggestion(Suggestion(kind: .symbol("star.fill"), reason: "test"))
        XCTAssertEqual(model.overlay.activeTab, .text)
        XCTAssertEqual(model.overlay.text, "before")
    }

}
