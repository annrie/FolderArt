# Finder クイックアクション (Services) 実装計画

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Finder の右クリック > クイックアクションから、アプリ画面を開かずにフォルダーへ「FolderArt で開く / 直前のお気に入りを適用 / アイコンを元に戻す」を実行できるようにする。

**Architecture:** 別ターゲットや App Group は作らず、本体アプリ自身が `NSServices` を宣言し `NSApp.servicesProvider` に提供オブジェクトを登録する。提供オブジェクトは pboard→[URL] 変換の薄い層で、実処理は既存の `AppModel` / `ApplyCoordinator` / `FolderIconManager` に委譲する。静かな 2 項目は、閉じた状態から起動された場合ウィンドウを出さず処理後に自分で終了する。

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, XcodeGen, XCTest。macOS 13。

**Spec:** `docs/superpowers/specs/2026-09-06-finder-quick-actions-design.md`

## Global Constraints

- macOS 13.0 / Swift 5.9 (非 strict concurrency)。新規依存は追加しない。
- **`xcodebuild` は必ずフォアグラウンド + `timeout: 600000`。バックグラウンド実行禁止。**
- 全テストコマンド:
  ```bash
  xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"
  ```
  プロジェクト由来の `warning:` は 0。`appintentsmetadataprocessor …` と意図的な `*** ERROR: CGImageSourceCreateThumbnailAtIndex … failed` は無視。
- 新規ファイルを作る Task は `xcodegen generate` を実行し、生成された `FolderArt.xcodeproj/project.pbxproj` をコミットに含める。
- 新規のユーザー可視文言は `scripts/localization/strings.json` に追加し 8 言語 (ja/en/de/es/fr/ko/pt-BR/zh-Hant、ja==キー) → `python3 scripts/localization/build-xcstrings.py` で再生成 → `--check` で missing 0。
- コミット本文末尾は必ず次の 2 行:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- サンドボックス/entitlements は現状維持 (`app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`)。新規 entitlement は足さない。
- main/develop へ直接コミットしない (作業ブランチ `feature/finder-quick-actions`)。
- バージョンは Task 4 で 1.6.0 / ビルド 9。

## File Structure

- Create `FolderArt/Stores/LastPresetStore.swift` — 「最後に使ったお気に入り」の id を 1 ファイルに永続化する薄いラッパ。
- Create `FolderArt/Services/QuickActionProvider.swift` — `NSServices` 提供オブジェクト (pboard→[URL] 変換 + AppModel 呼び出し)。
- Create `FolderArt/AppDelegate.swift` — 共有 `AppModel` の所有、`servicesProvider` 登録、静かな終了の制御。
- Modify `FolderArt/AppModel.swift` — `lastAppliedPresetID` 状態、`openFolders` / `applyLastPreset(to:)` / `resetIcons(at:)` / `directories(from:)`。
- Modify `FolderArt/FolderArtApp.swift` — `@NSApplicationDelegateAdaptor`、共有モデルを `ContentView` に注入。
- Modify `FolderArt/ContentView.swift` — `@StateObject var model = AppModel()` を `@EnvironmentObject var model: AppModel` に変更。
- Modify `project.yml` — Info.plist `NSServices` 3 項目、バージョン。
- Modify `scripts/localization/strings.json` + `FolderArt/Resources/Localizable.xcstrings` + `FolderArt/Resources/InfoPlist.xcstrings` — 文言。
- Modify `README.md` — 使い方・有効化・トラブルシュート・構成。
- Tests: `FolderArtTests/LastPresetStoreTests.swift`, `FolderArtTests/AppModelTests.swift` (追記), `FolderArtTests/QuickActionProviderTests.swift`。

---

### Task 1: 「直前のお気に入り」の永続化

**Files:**
- Create: `FolderArt/Stores/LastPresetStore.swift`
- Modify: `FolderArt/AppModel.swift` (init に `lastPresetStore` を注入、`applyPreset` で記録、`lastAppliedPreset` を公開)
- Test: `FolderArtTests/LastPresetStoreTests.swift`, `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `CodableStore<T: Codable>` (`load() throws -> T?`, `save(_:) throws`, `fileURL`)、`HistoryStore.appSupportDirectory`、`PresetStore.presets: [Preset]`、`Preset.id: UUID`。
- Produces: `LastPresetStore`(`init(storageURL:)`, `var id: UUID? { get set }`)、`AppModel.lastAppliedPreset: Preset?`、`AppModel.init(..., lastPresetStore:)`。

- [ ] **Step 1: LastPresetStore のテストを書く**

`FolderArtTests/LastPresetStoreTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class LastPresetStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LastPresetStoreTests_\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func url() -> URL { dir.appendingPathComponent("last-preset.json") }

    func testAbsentFileReadsNil() {
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }

    func testRoundTripsAcrossInstances() {
        let id = UUID()
        var a = LastPresetStore(storageURL: url())
        a.id = id
        let b = LastPresetStore(storageURL: url())
        XCTAssertEqual(b.id, id)
    }

    func testSettingNilClearsIt() {
        var a = LastPresetStore(storageURL: url())
        a.id = UUID()
        a.id = nil
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }

    func testCorruptFileReadsNil() throws {
        try "not json".data(using: .utf8)!.write(to: url())
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }
}
```

- [ ] **Step 2: 落ちることを確認**

Run: `xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' -only-testing:FolderArtTests/LastPresetStoreTests 2>&1 | grep -E "error:|Executed|TEST (SUCCEEDED|FAILED)"`
Expected: コンパイル失敗 (`LastPresetStore` 未定義)。

- [ ] **Step 3: LastPresetStore を実装**

`FolderArt/Stores/LastPresetStore.swift`:

```swift
import Foundation

/// 「最後に使ったお気に入り」の id を 1 ファイルに永続化する。読めない/壊れているときは nil。
struct LastPresetStore {
    private let store: CodableStore<UUID>

    init(storageURL: URL = HistoryStore.appSupportDirectory.appendingPathComponent("last-preset.json")) {
        store = CodableStore(fileURL: storageURL)
    }

    var id: UUID? {
        get { (try? store.load()) ?? nil }
        nonmutating set {
            if let value = newValue {
                try? store.save(value)
            } else if FileManager.default.fileExists(atPath: store.fileURL.path) {
                try? FileManager.default.removeItem(at: store.fileURL)
            }
        }
    }
}
```

- [ ] **Step 4: 通ることを確認**

Run: 同上。Expected: `Executed 4 tests, with 0 failures`。

- [ ] **Step 5: AppModel に配線するテストを書く**

`FolderArtTests/AppModelTests.swift` に追記 (既存の `root` 一時ディレクトリと `makeFolder` ヘルパを再利用):

```swift
func testApplyPresetRecordsLastAppliedPreset() throws {
    let store = LastPresetStore(storageURL: root.appendingPathComponent("last-preset.json"))
    let m = AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("h.json")),
                     presets: PresetStore(storageURL: root.appendingPathComponent("p.json")),
                     assets: AssetStore(directory: root.appendingPathComponent("a")),
                     userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
                     lastPresetStore: store,
                     runsMaintenance: false)
    let preset = try m.presets.add(name: "青", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
    m.applyPreset(preset)
    XCTAssertEqual(m.lastAppliedPreset?.id, preset.id)
    XCTAssertEqual(store.id, preset.id) // 永続化された
}

func testLastAppliedPresetIsNilWhenDeleted() throws {
    let store = LastPresetStore(storageURL: root.appendingPathComponent("last-preset.json"))
    let m = AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("h.json")),
                     presets: PresetStore(storageURL: root.appendingPathComponent("p.json")),
                     assets: AssetStore(directory: root.appendingPathComponent("a")),
                     userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
                     lastPresetStore: store,
                     runsMaintenance: false)
    let preset = try m.presets.add(name: "青", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
    m.applyPreset(preset)
    try m.presets.remove(preset)
    XCTAssertNil(m.lastAppliedPreset)          // 削除済み id は解決できない
}
```

- [ ] **Step 6: AppModel を実装**

`FolderArt/AppModel.swift`:
- init に引数を追加 (既定は実ファイル): `lastPresetStore: LastPresetStore = LastPresetStore(),` を `runsMaintenance` の直前に挿入。プロパティ `private let lastPresetStore: LastPresetStore` を保存。
- 公開プロパティを追加:
  ```swift
  /// 直前に使ったお気に入り (削除済み・未記録なら nil)
  var lastAppliedPreset: Preset? {
      guard let id = lastPresetStore.id else { return nil }
      return presets.presets.first { $0.id == id }
  }
  ```
- `applyPreset(_:)` の末尾で記録:
  ```swift
  func applyPreset(_ preset: Preset) {
      guard !isApplying else { return }
      overlay.restore(overlay: preset.overlay, settings: preset.settings)
      lastPresetStore.id = preset.id
  }
  ```

- [ ] **Step 7: フォーカステスト**

Run: `... -only-testing:FolderArtTests/LastPresetStoreTests -only-testing:FolderArtTests/AppModelTests 2>&1 | grep -E "error:| failed|Executed|TEST (SUCCEEDED|FAILED)"`
Expected: 全て成功。

- [ ] **Step 8: コミット**

```bash
git add FolderArt/Stores/LastPresetStore.swift FolderArt/AppModel.swift FolderArtTests/LastPresetStoreTests.swift FolderArtTests/AppModelTests.swift FolderArt.xcodeproj/project.pbxproj
# 新規ファイルがあるので事前に: xcodegen generate
git commit -m "feat: ✨ 直前に使ったお気に入りを永続化する (Quick Action の下ごしらえ)"
```
(コミット前に `xcodegen generate` を実行して pbxproj を更新すること)

---

### Task 2: Quick Action の AppModel メソッド

**Files:**
- Modify: `FolderArt/AppModel.swift`
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `ApplyCoordinator.apply(overlayImage:overlay:settings:to:progress:) async -> ApplyOutcome`、`ApplyCoordinator.reset(folder:) throws`、`OverlayRenderer.render(_:settings:side:assets:) -> NSImage?`、`IconComposer.iconSize`、`FolderSelection.add(_:)`、`lastAppliedPreset`、`hasHistory(_:)` (既存 private)。
- Produces: `AppModel.openFolders(_:)`、`AppModel.applyLastPreset(to:) async -> QuickApplyResult`、`AppModel.resetIcons(at:)`、`static AppModel.directories(from:) -> [URL]`。

- [ ] **Step 1: テストを書く**

`FolderArtTests/AppModelTests.swift` に追記:

```swift
func testDirectoriesFiltersOutFilesAndMissing() throws {
    let d1 = try makeFolder("d1"); let d2 = try makeFolder("d2")
    let file = root.appendingPathComponent("f.txt"); try "x".data(using: .utf8)!.write(to: file)
    let missing = root.appendingPathComponent("nope")
    let result = AppModel.directories(from: [d1, file, d2, missing])
    XCTAssertEqual(Set(result), Set([d1, d2].map { $0.standardizedFileURL }))
}

func testApplyLastPresetReturnsFalseWithoutLastPreset() async throws {
    let m = makeQuickActionModel()
    let d = try makeFolder("target")
    let ok = await m.applyLastPreset(to: [d])
    XCTAssertFalse(ok)
}

func testApplyLastPresetAppliesToGivenFoldersAndRecordsHistory() async throws {
    let m = makeQuickActionModel()
    let preset = try m.presets.add(name: "s", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
    m.applyPreset(preset)
    let d = try makeFolder("target")
    let ok = await m.applyLastPreset(to: [d])
    XCTAssertTrue(ok)
    XCTAssertTrue(m.history.tasks.contains { $0.folderPath == d.standardizedFileURL.path }) // 履歴に残る
}

func testResetIconsResetsOnlyFoldersWithHistory() async throws {
    let m = makeQuickActionModel()
    let preset = try m.presets.add(name: "s", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
    m.applyPreset(preset)
    let applied = try makeFolder("applied"); let untouched = try makeFolder("untouched")
    _ = await m.applyLastPreset(to: [applied])
    m.resetIcons(at: [applied, untouched])
    XCTAssertFalse(m.history.tasks.contains { $0.folderPath == applied.standardizedFileURL.path })
}

// ヘルパ (AppModelTests に追記)
private func makeQuickActionModel() -> AppModel {
    AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("h.json")),
             presets: PresetStore(storageURL: root.appendingPathComponent("p.json")),
             assets: AssetStore(directory: root.appendingPathComponent("a")),
             userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
             lastPresetStore: LastPresetStore(storageURL: root.appendingPathComponent("last-preset.json")),
             runsMaintenance: false)
}
```

- [ ] **Step 2: 落ちることを確認**

Run: `... -only-testing:FolderArtTests/AppModelTests 2>&1 | grep -E "error:|Executed|TEST"` → コンパイル失敗 (メソッド未定義)。

- [ ] **Step 3: 実装**

`FolderArt/AppModel.swift` に追加 (`// MARK: - Quick Action (Finder サービス)` として):

```swift
// MARK: - Quick Action (Finder サービス)

/// URL 群のうち、実在するディレクトリだけを standardized で返す (ファイル・欠落は除外)
static func directories(from urls: [URL]) -> [URL] {
    urls.compactMap { url in
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
        return url.standardizedFileURL
    }
}

/// フォルダーをリストに読み込んでアプリを前面化する (サービス「FolderArt で開く」)
func openFolders(_ urls: [URL]) {
    let dirs = Self.directories(from: urls)
    guard !dirs.isEmpty else { return }
    folders.add(dirs)
    NSApp.activate(ignoringOtherApps: true)
}

/// Quick Action の適用結果。呼び出し側 (QuickActionProvider) が前面化とアラートを判断する。
/// (Ruling 1: 全フォルダー失敗 = サンドボックス書き込み拒否を沈黙させないため 3 値にする)
enum QuickApplyResult: Equatable {
    case applied         // 1 つ以上のフォルダーに適用できた (静かに終了してよい)
    case noPreset        // 直前のお気に入りが無い/解決できない/対象フォルダーが無い
    case failed(String)  // お気に入りはあるが、描画に失敗 or 全フォルダーで失敗 (メッセージ付き)
}

/// 直前のお気に入りを、UI 状態に触れず指定フォルダーへ静かに適用する。
func applyLastPreset(to urls: [URL]) async -> QuickApplyResult {
    let dirs = Self.directories(from: urls)
    guard let preset = lastAppliedPreset, !dirs.isEmpty else { return .noPreset }
    guard let image = OverlayRenderer.render(preset.overlay, settings: preset.settings,
                                             side: IconComposer.iconSize.width, assets: assets) else {
        return .failed(String(localized: "お気に入りの絵柄を作れませんでした。"))
    }
    let started = dirs.filter { $0.startAccessingSecurityScopedResource() }
    defer { for u in started { u.stopAccessingSecurityScopedResource() } }
    let outcome = await coordinator.apply(overlayImage: image, overlay: preset.overlay,
                                          settings: preset.settings, to: dirs)
    reapAssets()
    if outcome.succeeded.isEmpty {
        return .failed(outcome.summary ?? String(localized: "フォルダーにアイコンを適用できませんでした。"))
    }
    return .applied
}

/// FolderArt が付けたアイコンだけを元に戻す (サービス「アイコンを元に戻す」)
func resetIcons(at urls: [URL]) {
    for url in Self.directories(from: urls) where hasHistory(url) {
        let started = url.startAccessingSecurityScopedResource()
        defer { if started { url.stopAccessingSecurityScopedResource() } }
        do { try coordinator.reset(folder: url) }
        catch { errorMessage = error.localizedDescription }
    }
    reapAssets()
}
```

注意: `assets` / `coordinator` は AppModel の既存 private プロパティ。`hasHistory(_:)` は既存 private。`reapAssets()` は既存。`applyLastPreset` は `isApplying` を立てない (UI のバッチと違い単発・裏方のため。競合が気になる場合は `guard !isApplying` を先頭に足すが、サービス起動時は基本 idle)。

- [ ] **Step 4: フォーカステスト**

Run: `... -only-testing:FolderArtTests/AppModelTests 2>&1 | grep -E "error:| failed|Executed|TEST"` → 全て成功。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/AppModel.swift FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ Quick Action 用の AppModel メソッド (開く/直前のお気に入りを適用/戻す)"
```

---

### Task 3: NSServices 提供オブジェクトとアプリ配線 (統合・実機検証あり)

**Files:**
- Create: `FolderArt/Services/QuickActionProvider.swift`
- Create: `FolderArt/AppDelegate.swift`
- Modify: `FolderArt/FolderArtApp.swift`, `FolderArt/ContentView.swift`, `project.yml`
- Test: `FolderArtTests/QuickActionProviderTests.swift`

**Interfaces:**
- Consumes: `AppModel.openFolders`/`applyLastPreset(to:)`/`resetIcons(at:)`、`AppModel.errorMessage`。
- Produces: `QuickActionProvider` (`@objc openFoldersInFolderArt`/`applyLastPreset`/`resetIcon`)、`AppDelegate` (共有 `AppModel`、`servicesProvider` 登録、静かな終了)。

- [ ] **Step 1: pboard→[URL] 抽出のテストを書く**

`FolderArtTests/QuickActionProviderTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class QuickActionProviderTests: XCTestCase {
    func testFolderURLsFromPasteboardExtractsFileURLs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QA_\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = NSPasteboard(name: .init("QATest_\(UUID())"))
        pb.clearContents()
        pb.writeObjects([dir as NSURL])
        let urls = QuickActionProvider.folderURLs(from: pb)
        XCTAssertEqual(urls.map { $0.standardizedFileURL }, [dir.standardizedFileURL])
    }

    func testFolderURLsFromEmptyPasteboardIsEmpty() {
        let pb = NSPasteboard(name: .init("QATestEmpty_\(UUID())"))
        pb.clearContents()
        XCTAssertTrue(QuickActionProvider.folderURLs(from: pb).isEmpty)
    }
}
```

- [ ] **Step 2: 落ちることを確認**

Run: `... -only-testing:FolderArtTests/QuickActionProviderTests 2>&1 | grep -E "error:|Executed|TEST"` → コンパイル失敗。

- [ ] **Step 3: QuickActionProvider を実装**

`FolderArt/Services/QuickActionProvider.swift`:

```swift
import AppKit

/// NSServices の提供オブジェクト。pboard からフォルダー URL を取り出し、AppModel に委譲する薄い層。
/// 実処理・エラー表示は AppModel 側。静かな 2 サービスの後始末 (静かな終了) は onSilentServiceFinished で通知する。
final class QuickActionProvider: NSObject {
    private let model: AppModel
    /// 静かなサービス (適用・戻す) が 1 つ完了するたびに呼ばれる。AppDelegate が「起動専用なら終了」を判断する。
    var onSilentServiceFinished: (() -> Void)?

    init(model: AppModel) { self.model = model }

    static func folderURLs(from pboard: NSPasteboard) -> [URL] {
        let options: [NSPasteboard.ReadingOptionKey: Any] = [.urlReadingFileURLsOnly: true]
        let objs = pboard.readObjects(forClasses: [NSURL.self], options: options) as? [URL] ?? []
        return AppModel.directories(from: objs)
    }

    @objc func openFoldersInFolderArt(_ pboard: NSPasteboard, userData: String?,
                                      error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in self.model.openFolders(urls) }
    }

    @objc func applyLastPreset(_ pboard: NSPasteboard, userData: String?,
                               error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in
            switch await self.model.applyLastPreset(to: urls) {
            case .applied:
                break // 静かに成功 (合図は Finder のアイコン変化)。onSilentServiceFinished で静かに終了しうる
            case .noPreset:
                self.model.errorMessage = String(localized: "まだお気に入りを使っていません。まず FolderArt でお気に入りを適用してください。")
                NSApp.activate(ignoringOtherApps: true)
            case .failed(let message):
                self.model.errorMessage = message
                NSApp.activate(ignoringOtherApps: true)
            }
            self.onSilentServiceFinished?()
        }
    }

    @objc func resetIcon(_ pboard: NSPasteboard, userData: String?,
                         error: AutoreleasingUnsafeMutablePointer<NSString>?) {
        let urls = Self.folderURLs(from: pboard)
        Task { @MainActor in
            self.model.resetIcons(at: urls)
            self.onSilentServiceFinished?()
        }
    }
}
```

- [ ] **Step 4: 通ることを確認**

Run: `... -only-testing:FolderArtTests/QuickActionProviderTests 2>&1 | grep -E "error:| failed|Executed|TEST"` → 成功。

- [ ] **Step 5: AppDelegate を実装 (共有モデル・登録・静かな終了)**

`FolderArt/AppDelegate.swift`:

```swift
import AppKit

/// 共有 AppModel を所有し、NSServices を登録する。閉じた状態からサービスのためだけに
/// 起動された場合は、ウィンドウを出さず処理完了後に静かに終了する。
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private lazy var provider = QuickActionProvider(model: model)

    /// ユーザーがウィンドウを出す前にサービスが呼ばれたら「起動専用」とみなす候補になる
    private var userOpenedWindow = false

    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.servicesProvider = provider
        provider.onSilentServiceFinished = { [weak self] in self?.terminateIfLaunchedForServiceOnly() }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // ウィンドウが可視 = ユーザーが使っている。以後は静かな終了をしない
        if NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) {
            userOpenedWindow = true
        }
    }

    /// 「FolderArt で開く」やユーザー操作でウィンドウが出ていれば終了しない。
    /// 起動専用 (ウィンドウ未表示) なら静かに終了する。
    private func terminateIfLaunchedForServiceOnly() {
        guard !userOpenedWindow,
              !NSApp.windows.contains(where: { $0.isVisible && $0.canBecomeMain }) else { return }
        NSApp.terminate(nil)
    }
}
```

注意: 静かな終了の可否はウィンドウ可視性で判定する。「FolderArt で開く」は `openFolders` 内で `NSApp.activate` しウィンドウが可視になるため、`onSilentServiceFinished` を呼ばない (open は静かなサービスではない)。適用/戻すは処理後に `onSilentServiceFinished` → ウィンドウが無ければ終了。既にアプリが開いていれば `userOpenedWindow` が true で終了しない。

- [ ] **Step 6: FolderArtApp と ContentView を配線**

`FolderArt/FolderArtApp.swift`:
```swift
@main
struct FolderArtApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var language = LanguageSetting()

    var body: some Scene {
        Window("FolderArt", id: "main") {
            ContentView()
                .environmentObject(appDelegate.model)   // 追加
                .environmentObject(language)
        }
        // ... 既存の windowStyle / commands はそのまま
    }
}
```

`FolderArt/ContentView.swift`:
```swift
// 変更前: @StateObject private var model = AppModel()
@EnvironmentObject private var model: AppModel
```

- [ ] **Step 7: project.yml に NSServices を追加**

`project.yml` の `FolderArt` ターゲットの `info.properties` に追加:
```yaml
        NSServices:
          - NSMenuItem: { default: "FolderArt で開く" }
            NSMessage: openFoldersInFolderArt
            NSPortName: FolderArt
            NSSendFileTypes: [public.folder]
            NSRequiredContext: {}
          - NSMenuItem: { default: "直前のお気に入りを適用" }
            NSMessage: applyLastPreset
            NSPortName: FolderArt
            NSSendFileTypes: [public.folder]
            NSRequiredContext: {}
          - NSMenuItem: { default: "アイコンを元に戻す" }
            NSMessage: resetIcon
            NSPortName: FolderArt
            NSSendFileTypes: [public.folder]
            NSRequiredContext: {}
```
その後 `xcodegen generate`。

- [ ] **Step 8: 全体テスト (フォアグラウンド)**

Run: 全テストコマンド。Expected: `Executed <N> tests, with 0 failures`、プロジェクト由来 warning 0、`** TEST SUCCEEDED **`。

- [ ] **Step 9: コミット**

```bash
xcodegen generate
git add FolderArt/Services/QuickActionProvider.swift FolderArt/AppDelegate.swift FolderArt/FolderArtApp.swift FolderArt/ContentView.swift project.yml FolderArt.xcodeproj/project.pbxproj FolderArtTests/QuickActionProviderTests.swift
git commit -m "feat: ✨ NSServices でフォルダーの右クリックにクイックアクション 3 項目を追加"
```

- [ ] **Step 10: 実機検証 (コントローラーが実施、唯一の技術リスク)**

Release ビルド → `~/アプリケーション/FolderArt.app` に置いて 1 度起動 → Finder でフォルダーを右クリック > クイックアクション。確認:
1. 3 項目が出る (日本語名)。
2. 「直前のお気に入りを適用」で **サンドボックス下でもアイコンが書き換わる** (最大の検証点)。書けなければフォールバック (この項目を「開く」に倒す) を Task で追加する。
3. 閉じた状態から「適用」「戻す」を実行 → ウィンドウが出ず、処理後アプリが残らない。
4. 「FolderArt で開く」で読み込み + 前面化。
5. 複数フォルダー選択で動く。

---

### Task 4: 文言・README・バージョン (コントローラー)

**Files:**
- Modify: `scripts/localization/strings.json` (+ 再生成された `Localizable.xcstrings`)
- Modify: `FolderArt/Resources/InfoPlist.xcstrings` (サービス表示名の 8 言語化)
- Modify: `README.md`, `project.yml` (1.6.0 / 9)

- [ ] **Step 1: エラー文言を strings.json に追加**

次の 3 キーを 8 言語で追加 (Task 2/3 が String(localized:) で使う文言と byte 一致させる): 「まだお気に入りを使っていません。まず FolderArt でお気に入りを適用してください。」「お気に入りの絵柄を作れませんでした。」「フォルダーにアイコンを適用できませんでした。」。`build-xcstrings.py` で再生成、`--check` で missing 0。

- [ ] **Step 2: サービス表示名の 8 言語化**

3 つのメニュー名 (「FolderArt で開く」「直前のお気に入りを適用」「アイコンを元に戻す」) を `InfoPlist.xcstrings` に追加し 8 言語化する (NSServices の表示名は InfoPlist のローカライズ経由)。`scripts/localization/infoplist.json` を使う仕組みがあればそれに合わせる。実機で右クリックの表示が言語に追従することを確認。

- [ ] **Step 3: README を更新 (日英併記)**

- 機能一覧に「Finder の右クリックからクイックアクション (開く/直前のお気に入りを適用/元に戻す)」。
- 新節「クイックアクション / Quick Actions」: 有効化 (本体を `/Applications` か `~/アプリケーション` に置いて 1 度起動、出ない場合はシステム設定 > キーボード > キーボードショートカット > サービス、または「機能拡張」でチェック)、3 項目の説明、静かに適用される旨。
- 「プロジェクト構成」に `AppDelegate.swift` / `QuickActionProvider.swift` / `LastPresetStore.swift`。

- [ ] **Step 4: バージョン**

`project.yml`: `MARKETING_VERSION: 1.6.0` / `CURRENT_PROJECT_VERSION: 9`。`xcodegen generate`。

- [ ] **Step 5: 全体テスト + --check + check-compiled.sh**

Run: 全テスト、`python3 scripts/localization/build-xcstrings.py --check`、`scripts/localization/check-compiled.sh`。Expected: 全成功、missing 0 (両方)。

- [ ] **Step 6: コミット**

```bash
git add scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArt/Resources/InfoPlist.xcstrings README.md project.yml FolderArt.xcodeproj/project.pbxproj
git commit -m "chore: 🔖 1.6.0 に更新し README (クイックアクション) と文言を整える"
```

---

## Self-Review (計画者チェック)

- **spec カバレッジ:** §3 の 3 サービス → Task 2/3。§5 last-used preset → Task 1。§6 起動と静かな終了 → Task 3 (AppDelegate)。§7 サンドボックス検証 → Task 3 Step 10。§8 エラー文言 → Task 3/4。§8 README → Task 4。
- **型整合:** `applyLastPreset(to:) async -> QuickApplyResult`、`resetIcons(at:)`、`directories(from:) -> [URL]`、`OverlayRenderer.render(_:settings:side:assets:)`、`coordinator.apply(overlayImage:overlay:settings:to:)`、`coordinator.reset(folder:)` は実コードと一致確認済み。
- **プレースホルダなし:** 各 Step に実コード/実コマンドあり。
- **リスク:** サービス経由の書き込み可否は Task 3 Step 10 で実機確認。不可ならフォローアップ Task で「適用/戻す」を「開く」に倒すフォールバックを実装する (spec §7)。
