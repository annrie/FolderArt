# 提案辞書 GUI エディタ Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** ユーザー提案辞書 (`suggestions-user.json`) をアプリ内の専用ウィンドウで追加・編集・削除できるようにする (手編集も併存)。

**Architecture:** 別ウィンドウ + エディタ専用 `DictionaryEditorModel` + 共有ファイル + 明示保存。既存の `SuggestionDictionary.normalizedUser` 検証・`SymbolGridView`・`FileWatcher` を再利用し、保存後は明示通知で本体 `AppModel` が確実に再読込する。

**Tech Stack:** Swift 5.9 + SwiftUI + AppKit (macOS 13+)。新規依存なし。

**Spec:** docs/superpowers/specs/2026-09-08-dictionary-editor-design.md

## Global Constraints

- macOS 13.0 / Swift 5.9 (非 strict concurrency)。新規依存なし。
- `xcodebuild` は必ずフォアグラウンド + `timeout: 600000`。バックグラウンド禁止。
- 全テスト: `xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"`。プロジェクト由来 warning 0。`appintentsmetadataprocessor` と意図的な `CGImageSourceCreateThumbnailAtIndex … failed` は無視。
- UI 文言は `scripts/localization/strings.json` に **8 言語** (ja/en/de/es/fr/ko/pt-BR/zh-Hant、ja==キー) で足し、`python3 scripts/localization/build-xcstrings.py` で `Localizable.xcstrings` を再生成。日本語 UI 文言を足す Task は同じコミットで strings.json に足すこと (`--check` missing 0 を保つ)。非 UI の日本語リテラルには `// loc-ignore`。
- 新規ファイルを作る Task は `xcodegen generate` して pbxproj をコミットに含める。
- コミット本文末尾は必ず:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- main/develop 直コミット禁止 (作業ブランチ `feature/dictionary-editor`)。バージョンは Task 5 で 1.8.0 / 12。

---

## File Structure

- Create `FolderArt/State/DictionaryEditorModel.swift` — エディタ専用状態と操作 (Task 2)。
- Create `FolderArt/Views/DictionaryEditorView.swift` — 専用ウィンドウの中身 (Task 3)。
- Modify `FolderArt/AppModel.swift` — 編集通知 + 反映メソッド (Task 1)。
- Modify `FolderArt/ContentView.swift` — 編集通知の購読 (Task 1)。
- Modify `FolderArt/FolderArtApp.swift` — 2 つ目の Window シーン + 「提案辞書を編集…」メニュー (Task 4)。
- Modify `scripts/localization/strings.json` + `FolderArt/Resources/Localizable.xcstrings` — 新規 UI 文言 (Task 3/4)。
- Modify `project.yml` + README.md — バージョン・説明 (Task 5)。
- Tests: `FolderArtTests/DictionaryEditorModelTests.swift` (Task 2)。

---

## Task 1: 編集通知と本体への反映 (AppModel + ContentView)

**Files:**
- Modify: `FolderArt/AppModel.swift`
- Modify: `FolderArt/ContentView.swift`
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Produces: `AppModel.userDictionaryEditedNotification: Notification.Name`、`AppModel.handleUserDictionaryEdited()` (エディタ保存後に呼ばれ、監視を確実に開始しつつ辞書を読み直す)。

`AppModel` には既に `userDictionaryURL`、`reloadUserDictionary()`、`private func startDictionaryWatcher()`、`revealUserDictionaryNotification` がある。

- [ ] **Step 1: テスト** — `FolderArtTests/AppModelTests.swift` に追加。ユーザー辞書を注入した AppModel で、外部からファイルに妥当な辞書を書いてから `handleUserDictionaryEdited()` を呼ぶと、提案が反映されることを検証。**既存の `testWatcherReloadsUserDictionaryAutomatically` と同じ道具** (`makeDictionaryModel(userDictionary:)`, `addFolders`, `hasSymbol(_:in:)`) を使う。手本にするその既存テストを先に読むこと。

```swift
func testHandleUserDictionaryEditedReloadsSuggestions() async throws {
    let user = root.appendingPathComponent("suggestions-user.json")
    let m = makeDictionaryModel(userDictionary: user)   // ← 既存ヘルパ (testWatcher... と同じ)
    m.addFolders([try makeFolder("xyzzy")])
    let before = m.dictionaryRebuildCount
    // FileWatcher に頼らず、直接ファイルを書いてから明示反映する
    try #"[{"keys": ["xyzzy"], "symbol": "star.fill", "emoji": "⭐"}]"#.write(to: user, atomically: true, encoding: .utf8)
    await m.handleUserDictionaryEdited()
    XCTAssertEqual(m.dictionaryRebuildCount, before + 1)
    XCTAssertTrue(hasSymbol("star.fill", in: m))          // ← 既存ヘルパ
}
```
(注: `makeDictionaryModel`/`hasSymbol`/`makeFolder` は既存 AppModelTests のヘルパ。名前・シグネチャが違えば実物に合わせる。`dictionaryRebuildCount + 1` は確実に効く検証。)

- [ ] **Step 2: 実行して失敗** — `handleUserDictionaryEdited` 未定義でコンパイル失敗。

- [ ] **Step 3: 実装** — `AppModel.swift` に追加:

```swift
/// エディタが保存した後に post される。ContentView が受けて本体の辞書を読み直す。
static let userDictionaryEditedNotification = Notification.Name("FolderArt.userDictionaryEdited")

/// 提案辞書エディタの保存後に呼ぶ。監視が始まっていなければ始め、辞書を読み直す。
/// (ファイルが今まで無く FileWatcher が監視していない場合でも確実に反映するため)
func handleUserDictionaryEdited() async {
    startDictionaryWatcher()
    await reloadUserDictionary()
}
```

- [ ] **Step 4: ContentView で購読** — `ContentView.swift` の `.onReceive(... revealUserDictionaryNotification ...)` の近くに追加:

```swift
.onReceive(NotificationCenter.default.publisher(for: AppModel.userDictionaryEditedNotification)) { _ in
    Task { await model.handleUserDictionaryEdited() }
}
```

- [ ] **Step 5: 実行して成功** — 追加テスト green + フルスイート green。

- [ ] **Step 6: コミット**

```bash
git add FolderArt/AppModel.swift FolderArt/ContentView.swift FolderArtTests/AppModelTests.swift
git commit  # feat: 🔔 提案辞書エディタの保存を本体に反映する通知を足す
```

---

## Task 2: DictionaryEditorModel (中核ロジック)

**Files:**
- Create: `FolderArt/State/DictionaryEditorModel.swift`
- Test: `FolderArtTests/DictionaryEditorModelTests.swift`

**Interfaces:**
- Consumes: `SuggestionDictionary.normalizedUser`、`SuggestionDictionary.loadUserSnapshot(at:)` (contentHash 取得)、`SuggestionEntry`、`UserDictionaryError`、`SymbolCatalog`、`AppModel.userDictionaryEditedNotification` (Task 1)。
- Produces: `DictionaryEditorModel` (下記 API)。

`SuggestionEntry { let keys: [String]; let symbol: String?; let emoji: String? }`。`normalizedUser(_ raw: [SuggestionEntry]) throws -> SuggestionDictionary` はキーを NFKC+小文字+trim・空/重複整理し、上限違反で `UserDictionaryError` を throw。`loadUserSnapshot(at:) -> (result: Result<SuggestionDictionary,Error>?, contentHash: Data)`。

- [ ] **Step 1: テスト (往復)** — `FolderArtTests/DictionaryEditorModelTests.swift`:

```swift
import XCTest
@testable import FolderArt

@MainActor
final class DictionaryEditorModelTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }
    private func url() -> URL { root.appendingPathComponent("suggestions-user.json") }

    func testReloadThenSaveRoundTrips() throws {
        let u = url()
        try #"[{"keys":["案件","project"],"symbol":"folder.fill","emoji":"🗂️"}]"#.write(to: u, atomically: true, encoding: .utf8)
        let m = DictionaryEditorModel(url: u)
        m.reload()
        XCTAssertEqual(m.rows.count, 1)
        XCTAssertEqual(m.rows[0].keys, ["案件", "project"])
        XCTAssertEqual(m.rows[0].symbol, "folder.fill")
        XCTAssertTrue(m.save())
        // ファイルは loadUser で同じ項目に読める (キーは正規化されて小文字化)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
        XCTAssertEqual(dict.entries.count, 1)
        XCTAssertEqual(dict.entries[0].symbol, "folder.fill")
        XCTAssertTrue(dict.entries[0].keys.contains("project"))
    }
}
```

- [ ] **Step 2: 実行して失敗** — 型未定義。

- [ ] **Step 3: 実装** — `FolderArt/State/DictionaryEditorModel.swift`:

```swift
import Foundation

@MainActor
final class DictionaryEditorModel: ObservableObject {
    struct Row: Identifiable, Equatable {
        let id = UUID()
        var keys: [String]
        var symbol: String?
        var emoji: String?
    }

    @Published private(set) var rows: [Row] = []
    @Published var selection: Row.ID?
    @Published private(set) var isDirty = false
    @Published var errorMessage: String?
    @Published var pendingExternalChange = false

    let catalog: SymbolCatalog
    private let url: URL
    private var loadedContentHash: Data?

    init(url: URL, catalog: SymbolCatalog = .shared) {
        self.url = url
        self.catalog = catalog
        reload()
    }

    /// 現在のファイルを読み直して rows を作る。無ければ空。読めない/壊れていれば errorMessage。
    func reload() {
        let snapshot = SuggestionDictionary.loadUserSnapshot(at: url)
        loadedContentHash = snapshot.contentHash
        pendingExternalChange = false
        isDirty = false
        selection = nil
        switch snapshot.result {
        case nil:
            rows = []                       // ファイル無し
        case .success(let dict):
            rows = dict.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        case .failure(let error):
            rows = []
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - 編集操作 (すべて isDirty を立てる)

    func addRow() {
        let row = Row(keys: [], symbol: nil, emoji: nil)
        rows.append(row); selection = row.id; isDirty = true
    }
    func deleteRows(_ ids: Set<Row.ID>) {
        rows.removeAll { ids.contains($0.id) }; isDirty = true
        if let sel = selection, ids.contains(sel) { selection = nil }
    }
    func addKey(_ raw: String, to id: Row.ID) {
        let key = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !key.isEmpty, let i = rows.firstIndex(where: { $0.id == id }) else { return }
        if !rows[i].keys.contains(key) { rows[i].keys.append(key); isDirty = true }
    }
    func removeKey(_ key: String, from id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].keys.removeAll { $0 == key }; isDirty = true
    }
    func setSymbol(_ name: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        rows[i].symbol = (name?.isEmpty == true) ? nil : name; isDirty = true
    }
    func setEmoji(_ emoji: String?, for id: Row.ID) {
        guard let i = rows.firstIndex(where: { $0.id == id }) else { return }
        let e = emoji?.trimmingCharacters(in: .whitespacesAndNewlines)
        rows[i].emoji = (e?.isEmpty == true) ? nil : e; isDirty = true
    }

    // MARK: - 保存

    /// rows → [SuggestionEntry] → normalizedUser 検証 → 外部変更確認 → アトミック書き出し。
    /// 検証エラーは errorMessage にして false。外部変更があれば (force でなければ) pendingExternalChange=true で false。
    @discardableResult
    func save(force: Bool = false) -> Bool {
        let entries = rows.map { SuggestionEntry(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        let normalized: SuggestionDictionary
        do {
            normalized = try SuggestionDictionary.normalizedUser(entries)
        } catch {
            errorMessage = error.localizedDescription
            return false
        }
        if !force {
            let current = SuggestionDictionary.loadUserSnapshot(at: url).contentHash
            if let loaded = loadedContentHash, current != loaded {
                pendingExternalChange = true
                return false
            }
        }
        do {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                    withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let data = try encoder.encode(normalized.entries)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "提案辞書を保存できません: \(error.localizedDescription)")
            return false
        }
        loadedContentHash = SuggestionDictionary.loadUserSnapshot(at: url).contentHash
        isDirty = false
        pendingExternalChange = false
        // 正規化後の姿を表示に反映
        rows = normalized.entries.map { Row(keys: $0.keys, symbol: $0.symbol, emoji: $0.emoji) }
        NotificationCenter.default.post(name: AppModel.userDictionaryEditedNotification, object: nil)
        return true
    }
}
```

- [ ] **Step 4: 実行して成功** — 往復テスト green。

- [ ] **Step 5: 追加テスト** — 検証・isDirty・外部変更・空ファイル作成:

```swift
func testSaveRejectsOverLimitKeysPerEntryAndKeepsFile() throws {
    let u = url()
    try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
    let m = DictionaryEditorModel(url: u); m.reload()
    let before = try Data(contentsOf: u)
    for n in 0...SuggestionDictionary.userMaxKeysPerEntry { m.addKey("k\(n)", to: m.rows[0].id) }
    XCTAssertFalse(m.save())
    XCTAssertNotNil(m.errorMessage)
    XCTAssertEqual(try Data(contentsOf: u), before)      // 書き換わっていない
}

func testEditsSetDirtyAndEmptyFileCreatedOnSave() throws {
    let u = url()                                          // ファイル無し
    let m = DictionaryEditorModel(url: u)
    XCTAssertFalse(m.isDirty)
    m.addRow(); m.addKey("メモ", to: m.rows[0].id); m.setEmoji("📝", for: m.rows[0].id)
    XCTAssertTrue(m.isDirty)
    XCTAssertTrue(m.save())
    XCTAssertTrue(FileManager.default.fileExists(atPath: u.path))
    guard case .success(let dict)? = SuggestionDictionary.loadUser(at: u) else { return XCTFail() }
    XCTAssertEqual(dict.entries.first?.emoji, "📝")
}

func testExternalChangeBlocksSaveUntilForcedOrReloaded() throws {
    let u = url()
    try #"[{"keys":["a"],"emoji":"⭐"}]"#.write(to: u, atomically: true, encoding: .utf8)
    let m = DictionaryEditorModel(url: u); m.reload()
    m.addRow(); m.addKey("b", to: m.rows.last!.id)
    // 外部で別内容に書き換える
    try #"[{"keys":["c"],"emoji":"🎵"}]"#.write(to: u, atomically: true, encoding: .utf8)
    XCTAssertFalse(m.save())                               // 外部変更で止まる
    XCTAssertTrue(m.pendingExternalChange)
    XCTAssertTrue(m.save(force: true))                     // 上書きは通る
    XCTAssertFalse(m.pendingExternalChange)
}
```

- [ ] **Step 6: 実行して成功** — 全テスト green。

- [ ] **Step 7: xcodegen + コミット**

```bash
xcodegen generate
git add FolderArt/State/DictionaryEditorModel.swift FolderArtTests/DictionaryEditorModelTests.swift FolderArt.xcodeproj/project.pbxproj
git commit  # feat: ✨ 提案辞書エディタの状態モデル (往復・検証・外部変更・空ファイル作成)
```

---

## Task 3: DictionaryEditorView (専用ウィンドウの中身)

**Files:**
- Create: `FolderArt/Views/DictionaryEditorView.swift`
- Modify: `scripts/localization/strings.json` + `FolderArt/Resources/Localizable.xcstrings`
- Test: (UI 中心のためユニットテストは最小。ビルドが通ることを主眼)

**Interfaces:**
- Consumes: `DictionaryEditorModel` (Task 2)、`SymbolGridView(catalog:selected:)`。

- [ ] **Step 1: 文言を strings.json に追加** — 以下のキーを 8 言語で `scripts/localization/strings.json` に追加 (ja==キー、自然な訳)。キー例:
  - `"提案辞書の編集"` (ウィンドウ/見出し)
  - `"項目を追加"`, `"項目を削除"`, `"(キー未設定)"`
  - `"キー"`, `"キーを追加"`, `"記号"`, `"記号をクリア"`, `"絵文字"`, `"クリア"`
  - `"左で項目を選ぶか＋で追加してください"`
  - `"保存"`, `"閉じる"`
  - `"ファイルが変更されています。上書きしますか？ 読み直しますか？"`, `"上書き"`, `"読み直す"`
  - `"提案辞書を保存できません: %@"` (Task 2 で使用済みなら重複させない — 既にあるものは足さない)

  追加後: `python3 scripts/localization/build-xcstrings.py` で再生成し、`python3 scripts/localization/build-xcstrings.py --check` が missing 0 になることを確認。

- [ ] **Step 2: View 実装** — `FolderArt/Views/DictionaryEditorView.swift`。左リスト + 右詳細 + 保存バー。`@StateObject` でモデルを保持 (init で url/catalog を渡す)。要点:

```swift
import SwiftUI

struct DictionaryEditorView: View {
    @StateObject private var model: DictionaryEditorModel
    @Environment(\.dismiss) private var dismiss

    init(url: URL, catalog: SymbolCatalog = .shared) {
        _model = StateObject(wrappedValue: DictionaryEditorModel(url: url, catalog: catalog))
    }

    var body: some View {
        HSplitView {
            listPane.frame(minWidth: 220)
            detailPane.frame(minWidth: 380)
        }
        .frame(minWidth: 680, minHeight: 460)
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear { model.reload() }               // 開くたびに最新化
        .alert("お知らせ", isPresented: Binding(get: { model.errorMessage != nil },
                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("ファイルが変更されています。上書きしますか？ 読み直しますか？", isPresented: $model.pendingExternalChange) {
            Button("上書き") { model.save(force: true) }
            Button("読み直す", role: .cancel) { model.reload() }
        }
    }
    // listPane: List(selection:) で rows、下部に ＋/− ボタン
    // detailPane: 選択行のキー編集 (チップ + 追加欄) + SymbolGridView(catalog: model.catalog, selected: <binding>) + 絵文字 TextField
    // saveBar: 「保存」(model.isDirty で活性) と「閉じる」(dismiss)
}
```
  詳細ペインの記号は `SymbolGridView(catalog: model.catalog, selected: symbolBinding)` を埋め込む。`symbolBinding` は選択行の symbol を読み書きする `Binding<String?>` を手で作り、`set` で `model.setSymbol(...)` を呼ぶ (Task 2 の操作経由で isDirty を立てる)。キー・絵文字も同様に model の操作を通す。

- [ ] **Step 3: ビルド確認** — `xcodegen generate` 後、フルスイートを実行してコンパイル + 既存テスト green (View 自体のユニットテストは無くてよいが、ビルドが通ること)。`--check` missing 0。

- [ ] **Step 4: コミット**

```bash
xcodegen generate
git add FolderArt/Views/DictionaryEditorView.swift scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArt.xcodeproj/project.pbxproj
git commit  # feat: 🎨 提案辞書エディタの画面 (項目一覧・キー編集・記号/絵文字選択)
```

---

## Task 4: Window シーン + メニュー (FolderArtApp)

**Files:**
- Modify: `FolderArt/FolderArtApp.swift`
- Modify: `scripts/localization/strings.json` + `FolderArt/Resources/Localizable.xcstrings` (「提案辞書を編集…」)

**Interfaces:**
- Consumes: `DictionaryEditorView` (Task 3)、`appDelegate.model.userDictionaryURL`。

- [ ] **Step 1: 文言** — `"提案辞書を編集…"` を strings.json に 8 言語で追加、再生成、`--check` missing 0。

- [ ] **Step 2: Window シーン + メニュー** — `FolderArtApp.swift`:
  - `@Environment(\.openWindow) private var openWindow` を `body` から使えるよう、`FolderArtApp` に持てないため、メニューのボタンは既存パターン (Notification) でも、`openWindow` を使う小さなラッパ View でもよい。最も素直なのは 2 つ目の `Window` シーンを足し、「ファイル」メニューのボタンで `openWindow(id:)` を呼ぶ。`openWindow` は Scene/View の環境値なので、`.commands` 内では使えない点に注意 → メニューボタンは Notification を post し、`ContentView` (環境に openWindow を持つ) が受けて `openWindow(id: "dictionary-editor")` する形にする (既存の revealUserDictionary と同じ Notification パターン)。

```swift
// Scene に追加
Window("提案辞書の編集", id: "dictionary-editor") {
    DictionaryEditorView(url: appDelegate.model.userDictionaryURL)
        .environmentObject(language)
}
.windowResizability(.contentMinSize)
.defaultSize(width: 720, height: 520)

// 「ファイル」メニュー (既存 CommandGroup(after: .importExport) 内、「提案辞書を開く…」の隣) に:
Button("提案辞書を編集…") {
    NotificationCenter.default.post(name: AppModel.openDictionaryEditorNotification, object: nil)
}
```
  `AppModel.openDictionaryEditorNotification` を足し、`ContentView` に `@Environment(\.openWindow) private var openWindow` と `.onReceive(... openDictionaryEditorNotification ...) { openWindow(id: "dictionary-editor") }` を追加する。

- [ ] **Step 3: ビルド + 実行確認 (コントローラー)** — フルスイート green、`--check` missing 0。コントローラーがビルドしたアプリで「ファイル > 提案辞書を編集…」がウィンドウを開き、項目の追加・保存ができ、本体の提案に反映されることを実機で確認。

- [ ] **Step 4: コミット**

```bash
xcodegen generate
git add FolderArt/FolderArtApp.swift FolderArt/ContentView.swift scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArt.xcodeproj/project.pbxproj
git commit  # feat: 🪟 「提案辞書を編集…」で専用ウィンドウを開く
```

---

## Task 5: バージョン・README・仕上げ (コントローラー)

**Files:** `project.yml`, `README.md`

- [ ] **Step 1: バージョン** — `MARKETING_VERSION: 1.8.0` / `CURRENT_PROJECT_VERSION: 12`。`xcodegen generate`。
- [ ] **Step 2: README (日英併記)** — 機能一覧と「提案辞書のカスタマイズ」節に「アプリ内エディタ (ファイル > 提案辞書を編集…) で追加・編集・削除できる (手編集も可)」を追記。
- [ ] **Step 3: 全テスト + `--check` + `check-compiled.sh`** — すべて成功・missing 0。
- [ ] **Step 4: コミット** — `chore: 🔖 1.8.0 に更新し README に辞書エディタを載せる`
- [ ] **Step 5: 仕上げ (コントローラー)** — 実機確認 (エディタで追加→保存→右クリックやメイン画面の提案に反映) → Codex 事前レビュー (フォアグラウンド) → PR (日英併記) → Codex 対応 (尽きるまで) → ユーザー確認後マージ → main 同期 → Release v1.8.0 → アプリ入れ替え。

---

## Self-Review (計画者チェック)

- **spec カバレッジ:** DictionaryEditorModel=Task 2、View=Task 3、Window+メニュー=Task 4、保存後反映の通知=Task 1、検証/外部変更/空ファイル=Task 2、バージョン/README=Task 5。全網羅。
- **型整合:** `DictionaryEditorModel.Row`/`rows`/`save(force:)`/`reload()`、`AppModel.userDictionaryEditedNotification`/`handleUserDictionaryEdited()`/`openDictionaryEditorNotification`、`DictionaryEditorView(url:catalog:)`、`SymbolGridView(catalog:selected:)`、`SuggestionDictionary.normalizedUser`/`loadUserSnapshot`/`loadUser`。実コードと一致。
- **依存順:** Task 1 (通知) → Task 2 (モデルが通知を post) → Task 3 (View がモデル使用) → Task 4 (Window が View 使用 + 別通知) → Task 5。
- **プレースホルダ:** Task 1 の提案検証アサーションは既存ヘルパに合わせて調整と明記 (曖昧さは残すが `dictionaryRebuildCount` の確実な検証を主にする)。UI の細部 (SwiftUI レイアウト) は View の craft に委ね、キー/記号/絵文字は必ず model の操作を通す点を固定。
- **リスク:** SwiftUI の 2 つ目 `Window` とモデル寿命 → 開くたび `onAppear reload()` で最新化。`openWindow` は環境値なので `.commands` から直接呼べない → Notification 経由で ContentView が openWindow。実機確認 (Task 4 Step 3 / Task 5 Step 5) 必須。
