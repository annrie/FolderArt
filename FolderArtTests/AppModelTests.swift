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
            // 実機の Application Support の辞書を読まないよう、存在しないディレクトリの下を指す (監視も始まらない)
            userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
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
                         // 実機の Application Support の辞書を読まないよう、存在しないディレクトリの下を指す (監視も始まらない)
                         userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
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

    func testExportPackSubsetWritesOnlySelected() throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        try model.presets.add(name: "月", overlay: .symbol(name: "moon.fill"), settings: CompositionSettings())
        let moon = try XCTUnwrap(model.presets.presets.first { $0.name == "月" })
        let file = root.appendingPathComponent("subset.folderartpack")
        model.exportPack(to: file, presets: [moon])
        XCTAssertNil(model.errorMessage)
        let pack = try PackReader.read(try Data(contentsOf: file))
        XCTAssertEqual(pack.presets.map(\.name), ["月"])
    }

    func testExportPackEmptySubsetExplainsAndWritesNothing() throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let file = root.appendingPathComponent("empty.folderartpack")
        model.exportPack(to: file, presets: [])
        XCTAssertEqual(model.errorMessage, String(localized: "書き出せるお気に入りがありません。"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
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
        XCTAssertEqual(model.errorMessage, String(localized: "書き出せるお気に入りがありません。"))
    }


    func testApplySuggestionIsIgnoredWhileApplying() {
        model.overlay.activeTab = .text
        model.overlay.text = "before"
        model.isApplying = true
        model.applySuggestion(Suggestion(kind: .symbol("star.fill"), reason: "test"))
        XCTAssertEqual(model.overlay.activeTab, .text)
        XCTAssertEqual(model.overlay.text, "before")
    }

    // MARK: - 中身の走査

    /// 走査の呼び出しを記録し、フォルダ名ごとにゲート (足止め) と結果を差し替えられる scanner (メインの外から呼ばれる)。
    /// 可変状態はすべて lock 越しにアクセスする。`configure` はモデルを作る前 (まだ並行アクセスが無いうち) に 1 回だけ呼ぶ
    private final class ScanRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        private var returned: [String: Int] = [:]
        private var results: [String: ContentSummary] = [:]
        private var gates: [String: DispatchSemaphore] = [:]

        /// フォルダ名ごとの結果と、任意でゲート (record がそこで足止めされ、signal() されるまで戻らない) を設定する
        func configure(results: [String: ContentSummary] = [:], gates: [String: DispatchSemaphore] = [:]) {
            lock.lock()
            self.results = results
            self.gates = gates
            lock.unlock()
        }

        /// 呼び出し順は calls に積んだ時点 (足止めの前) で確定する。ゲートがあれば signal() されるまでここで待つ
        func record(_ url: URL) -> ContentSummary? {
            let name = url.lastPathComponent
            lock.lock()
            calls.append(name)
            let gate = gates[name]
            let result = results[name]
            lock.unlock()
            gate?.wait()
            lock.lock(); returned[name, default: 0] += 1; lock.unlock()
            return result ?? ContentSummary(counts: [:], dominant: nil, representative: nil)
        }

        func count(of name: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return calls.filter { $0 == name }.count
        }

        /// record がゲートを抜けて実際に戻った回数 (呼ばれた回数の count(of:) とは別で見る)
        func returnedCount(of name: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return returned[name] ?? 0
        }
    }

    /// 固定の sleep に頼らず、期限まで観測可能な状態をポーリングする (走査は非同期で完了までの時間を保証できないため)
    private func waitUntil(_ timeout: TimeInterval = 5, _ condition: @escaping () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition() && Date() < deadline {
            try await Task.sleep(nanoseconds: 10_000_000)
        }
    }

    private func makeModel(scanner: ScanRecorder) -> AppModel {
        AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("history2.json")),
                 presets: PresetStore(storageURL: root.appendingPathComponent("presets2.json")),
                 assets: AssetStore(directory: root.appendingPathComponent("assets2")),
                 // 実機の Application Support の辞書を読まないよう、存在しないディレクトリの下を指す (監視も始まらない)
                 userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
                 contentScanner: { scanner.record($0) },
                 runsMaintenance: false)
    }

    /// 実際に読める PNG を 1 枚持つフォルダと、その代表画像
    private func makeFolderWithImage(_ name: String) throws -> (folder: URL, image: RepresentativeImage) {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try XCTUnwrap(TestSupport.bitmap(of: TestSupport.makeSolidImage(size: CGSize(width: 16, height: 16), color: .red))
            .representation(using: .png, properties: [:]))
        let file = folder.appendingPathComponent("photo.png")
        try png.write(to: file)
        return (folder, RepresentativeImage(url: file, modificationDate: Date(), thumbnailPNG: png))
    }

    private func imageSummary(_ image: RepresentativeImage) -> ContentSummary {
        ContentSummary(counts: [.image: 1], dominant: .image, representative: image)
    }

    private func hasImageChip(_ m: AppModel) -> Bool {
        m.suggestions.contains { if case .image = $0.kind { return true }; return false }
    }

    func testContentScanAddsImageChipWhenFolderStaysSelected() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.configure(results: ["A": imageSummary(image)])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        XCTAssertFalse(hasImageChip(m))   // 走査は非同期。同期の時点では名前の候補だけ
        try await waitUntil { self.hasImageChip(m) }
        XCTAssertTrue(hasImageChip(m))
        XCTAssertTrue(m.suggestions.contains { $0.kind == .emoji("📷") })   // 中身の多数派 (画像) の絵文字も入る
        XCTAssertEqual(scanner.count(of: "A"), 1)
    }

    func testStaleScanResultIsDiscardedWhenSourceChanges() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let scanner = ScanRecorder()
        let gateA = DispatchSemaphore(value: 0)
        defer { gateA.signal() }
        scanner.configure(results: ["A": imageSummary(image)], gates: ["A": gateA])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])   // A の走査が始まる (gateA で足止めされる)
        try await waitUntil { scanner.count(of: "A") == 1 }   // A の走査が確実に始まってから対象を変える
        m.addFolders([b])   // 対象が B に変わる → A はまだ足止め中なので、変更が先に来ることが構造上保証される
        XCTAssertEqual(m.suggestionSourceFolder, b.standardizedFileURL)
        gateA.signal()   // A の走査を進める。世代がずれているので結果は棄却されるはず
        try await waitUntil { scanner.returnedCount(of: "A") == 1 }
        XCTAssertFalse(hasImageChip(m))
    }

    func testReAddingSameFolderScansAgainWithNewGeneration() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.configure(results: ["A": imageSummary(image)])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await waitUntil { self.hasImageChip(m) }
        XCTAssertTrue(hasImageChip(m))
        m.folders.removeAll()
        XCTAssertTrue(m.suggestions.isEmpty)
        m.addFolders([a])
        try await waitUntil { self.hasImageChip(m) }
        XCTAssertTrue(hasImageChip(m))
        XCTAssertEqual(scanner.count(of: "A"), 2)
    }

    func testPresetChangeReusesContentWithoutRescan() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.configure(results: ["A": imageSummary(image)])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await waitUntil { self.hasImageChip(m) }
        try m.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        // お気に入りの追加は CombineLatest3 経由で同期的に候補を作り直す。走査はし直されないはず
        XCTAssertEqual(scanner.count(of: "A"), 1)
        XCTAssertTrue(hasImageChip(m))   // 使い回した結果で候補が作り直される
    }

    func testScanResultIsDroppedWhenListBecomesEmpty() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        let gateA = DispatchSemaphore(value: 0)
        defer { gateA.signal() }
        scanner.configure(results: ["A": imageSummary(image)], gates: ["A": gateA])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await waitUntil { scanner.count(of: "A") == 1 }   // A の走査が確実に始まってから空にする
        m.folders.removeAll()   // 走査中に対象が無くなる → cancel、戻ってきても採らない
        XCTAssertTrue(m.suggestions.isEmpty)
        gateA.signal()   // 足止めしていた A の走査を進める
        try await waitUntil { scanner.returnedCount(of: "A") == 1 }
        XCTAssertTrue(m.suggestions.isEmpty)
        XCTAssertEqual(scanner.count(of: "A"), 1)   // 走査は 1 回だけ始まり、その結果は棄却された (再走査もされていない)
    }

    /// A を走査済みの状態で B に切り替え (走査中)、B の走査が終わる前に A へ戻ると
    /// A はキャッシュ命中なので開始条件が満たされず、scanningFolder が B のまま固まってしまっていた。
    /// B の結果は棄却されつつ scanningFolder / contentScanTask を戻し、B に戻ったときまた走査できることを確認する
    func testReturningToCachedFolderDuringScanCancelsAndAllowsRescan() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let scanner = ScanRecorder()
        let gateB = DispatchSemaphore(value: 0)
        defer { gateB.signal() }
        scanner.configure(results: ["A": imageSummary(image)], gates: ["B": gateB])
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await waitUntil { self.hasImageChip(m) }   // A はキャッシュ済み (画像チップあり)
        XCTAssertTrue(hasImageChip(m))
        m.addFolders([b])   // B の走査が始まる (gateB で足止めされる)
        try await waitUntil { scanner.count(of: "B") == 1 }   // B の走査が確実に始まってから A へ戻る
        m.folders.selectedIDs = [a.standardizedFileURL]   // B の走査中に A へ戻る (A はキャッシュ命中なので同期で反映される)
        try await waitUntil { self.hasImageChip(m) }
        XCTAssertTrue(hasImageChip(m))
        gateB.signal()   // 1 回目の B の走査を進める (対象はもう A なので棄却されるはず)
        try await waitUntil { scanner.returnedCount(of: "B") == 1 }
        m.folders.selectedIDs = [b.standardizedFileURL]   // 再び B に戻る → 再走査されるべき
        try await waitUntil { scanner.count(of: "B") == 2 }   // 2 回目の走査が始まった (固まっていない証拠)
        gateB.signal()   // 2 回目の走査も進めて後始末する (テストを跨いでスレッドを足止めしたままにしない)
        try await waitUntil { scanner.returnedCount(of: "B") == 2 }
        XCTAssertEqual(m.suggestionSourceFolder, b.standardizedFileURL)
        XCTAssertEqual(scanner.count(of: "B"), 2)
    }

    /// 一括追加 (ドロップ・パネルでの複数選択) は 1 回の走査にまとまるべき。
    /// FolderSelection.add がフォルダごとに $folders を公開していた頃は、A → B → C と追加のたびに
    /// 走査が始まっては cancel される (cancel は列挙前の I/O までは止められないので A, B も実際に走査されてしまう)
    func testAddingFoldersInBatchScansOnlyTheLastFolder() async throws {
        let a = root.appendingPathComponent("A")
        let b = root.appendingPathComponent("B")
        let c = root.appendingPathComponent("C")
        for d in [a, b, c] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }
        let empty = ContentSummary(counts: [:], dominant: nil, representative: nil)
        let scanner = ScanRecorder()
        scanner.configure(results: ["A": empty, "B": empty, "C": empty])
        let m = makeModel(scanner: scanner)
        m.addFolders([a, b, c])
        try await waitUntil { scanner.count(of: "C") == 1 }
        XCTAssertEqual(scanner.count(of: "A"), 0)
        XCTAssertEqual(scanner.count(of: "B"), 0)
        XCTAssertEqual(m.suggestionSourceFolder, c.standardizedFileURL)
    }

    func testApplyingImageSuggestionCopiesIntoAssetsAndSwitchesTab() throws {
        let (_, image) = try makeFolderWithImage("A")
        model.applySuggestion(Suggestion(kind: .image(image), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .image)
        XCTAssertNotNil(model.overlay.imageAssetID)
        XCTAssertNil(model.errorMessage)
    }

    func testApplyingMissingImageSuggestionReportsError() {
        let missing = RepresentativeImage(url: root.appendingPathComponent("gone.png"), modificationDate: Date(), thumbnailPNG: Data())
        model.applySuggestion(Suggestion(kind: .image(missing), reason: ""))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.overlay.imageAssetID)
    }

    // MARK: - ユーザー辞書

    private var testDictionary: SuggestionDictionary {
        SuggestionDictionary(entries: [SuggestionEntry(keys: ["photo"], symbol: "photo.fill", emoji: "📷")])
    }

    /// ユーザー辞書の URL を注入したモデル。ディレクトリ (root) は既にあるので init で監視が始まる
    private func makeDictionaryModel(userDictionary: URL) -> AppModel {
        AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("history3.json")),
                 presets: PresetStore(storageURL: root.appendingPathComponent("presets3.json")),
                 assets: AssetStore(directory: root.appendingPathComponent("assets3")),
                 dictionary: testDictionary,
                 catalog: SymbolCatalog.shared,
                 userDictionaryURL: userDictionary,
                 runsMaintenance: false)
    }

    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func hasSymbol(_ name: String, in m: AppModel) -> Bool {
        m.suggestions.contains { $0.kind == .symbol(name) }
    }

    func testReloadUserDictionaryChangesSuggestions() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("xyzzy")])
        XCTAssertFalse(hasSymbol("star.fill", in: m))
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill", "emoji": "⭐"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(hasSymbol("star.fill", in: m))
        XCTAssertNil(m.errorMessage)
    }

    func testUserDictionaryOverridesBundledKey() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("photo")])
        XCTAssertTrue(hasSymbol("photo.fill", in: m))
        try #"[{"keys": ["photo"], "symbol": "camera.fill", "emoji": "📸"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(hasSymbol("camera.fill", in: m))
        XCTAssertFalse(hasSymbol("photo.fill", in: m))
    }

    func testBrokenUserDictionaryAlertsOncePerContentAndRecovers() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        let prefix = String(localized: "提案辞書を読めません: \("")")
        try "{ broken".write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false, m.errorMessage ?? "nil")
        m.errorMessage = nil
        await m.reloadUserDictionary()          // 同じ内容ではもう出ない
        XCTAssertNil(m.errorMessage)
        try "{ broken again".write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()          // 内容が変われば 1 回出る
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false)
        m.errorMessage = nil
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()          // 直せば黙って復帰する
        XCTAssertNil(m.errorMessage)
        m.addFolders([try makeFolder("xyzzy")])
        XCTAssertTrue(hasSymbol("star.fill", in: m))
    }

    /// 上限 (1 MB) を超えるファイルは、指紋のための読み込みでも全体を読まずサイズだけで区別する。
    /// それでも「内容ごとに 1 回」のアラートは出る (0 回にならない)
    func testOversizedUserDictionaryAlertsOnce() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        let prefix = String(localized: "提案辞書を読めません: \("")")
        let oversized = "[" + String(repeating: " ", count: SuggestionDictionary.userMaxFileBytes + 1)
        try oversized.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false, m.errorMessage ?? "nil")
        m.errorMessage = nil
        await m.reloadUserDictionary()          // 同じ内容ではもう出ない
        XCTAssertNil(m.errorMessage)
    }

    /// 読めないファイル (権限エラーなど) でも、指紋がサイズ+エラー文から作られるため黙らずに 1 回はアラートが出る
    func testUnreadableUserDictionaryAlertsOnce() async throws {
        try XCTSkipIf(geteuid() == 0, "root ではパーミッションで弾けない")
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        try m.prepareUserDictionaryFile()
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: user.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: user.path) }
        let prefix = String(localized: "提案辞書を読めません: \("")")
        await m.reloadUserDictionary()
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false, m.errorMessage ?? "nil")
        m.errorMessage = nil
        await m.reloadUserDictionary()          // 同じ内容ではもう出ない
        XCTAssertNil(m.errorMessage)
    }

    func testPrepareUserDictionaryFileWritesTemplateOnce() throws {
        let user = root.appendingPathComponent("sub/dir/suggestions-user.json")   // ディレクトリごと無い
        let m = makeDictionaryModel(userDictionary: user)
        let url = try m.prepareUserDictionaryFile()
        XCTAssertEqual(url, user)
        XCTAssertEqual(try String(contentsOf: user, encoding: .utf8), SuggestionDictionary.userTemplate)
        try "[]".write(to: user, atomically: true, encoding: .utf8)
        try m.prepareUserDictionaryFile()        // 既にあれば上書きしない
        XCTAssertEqual(try String(contentsOf: user, encoding: .utf8), "[]")
    }

    func testWatcherReloadsUserDictionaryAutomatically() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("xyzzy")])
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill", "emoji": "⭐"}]"#.write(to: user, atomically: true, encoding: .utf8)
        try await waitUntil { self.hasSymbol("star.fill", in: m) }
        XCTAssertTrue(hasSymbol("star.fill", in: m))
    }

    func testStartupErrorsAreJoined() async throws {
        let historyURL = root.appendingPathComponent("history4.json")
        try "{ broken history".write(to: historyURL, atomically: true, encoding: .utf8)
        let user = root.appendingPathComponent("suggestions-user.json")
        try "{ broken dictionary".write(to: user, atomically: true, encoding: .utf8)
        let m = AppModel(history: HistoryStore(storageURL: historyURL),
                         presets: PresetStore(storageURL: root.appendingPathComponent("presets4.json")),
                         assets: AssetStore(directory: root.appendingPathComponent("assets4")),
                         dictionary: testDictionary, catalog: SymbolCatalog.shared,
                         userDictionaryURL: user, runsMaintenance: false)
        let saved = String(localized: "保存データの読み込みに失敗しました: \("")")
        let dict = String(localized: "提案辞書を読めません: \("")")
        XCTAssertTrue(m.errorMessage?.hasPrefix(saved) ?? false)
        try await waitUntil { m.errorMessage?.contains(dict) ?? false }
        XCTAssertTrue(m.errorMessage?.contains(dict) ?? false)        // 待った条件そのものを確かめる
        XCTAssertTrue(m.errorMessage?.hasPrefix(saved) ?? false)      // 保存データのエラーは残る
        XCTAssertTrue(m.errorMessage?.contains("\n\n") ?? false)      // 空行で連結
    }

}
