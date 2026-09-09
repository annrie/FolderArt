# FolderArt 第7段階(本体) 設計 — 提案辞書の GUI 編集

**日付:** 2026-09-08

**Goal:** ユーザー提案辞書 (`suggestions-user.json`) を、Finder での手編集に加えてアプリ内の専用ウィンドウで追加・編集・削除できるようにする。

**Architecture:** 別ウィンドウ (`Window(id: "dictionary-editor")`) に、エディタ専用の状態を持つ `DictionaryEditorModel` (`@MainActor ObservableObject`) を置く。開いたときに現在の `suggestions-user.json` を読み、編集可能な行として保持。保存時に既存の `SuggestionDictionary.normalizedUser` で検証してからアトミックに書き出し、既存の `FileWatcher` が本体 `AppModel` の辞書を自動再読込する。エディタは本体の `AppModel` を作り直さない (資産回収衝突を避けるための単一 AppModel 方針を維持)。

**Tech Stack:** Swift 5.9 + SwiftUI + AppKit (macOS 13+)。新規依存なし。既存の `SuggestionDictionary`/`SuggestionEntry`/`normalizedUser`/`UserDictionaryError`/`SymbolCatalog`/`SymbolGridView` を再利用。

**Spec:** this file.

## Global Constraints

- macOS 13.0 / Swift 5.9 (非 strict concurrency)。新規依存なし。
- `xcodebuild` は必ずフォアグラウンド + `timeout: 600000`。バックグラウンド禁止。
- 全テスト: `xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"`。プロジェクト由来 warning 0。`appintentsmetadataprocessor` と意図的な `CGImageSourceCreateThumbnailAtIndex … failed` は無視。
- 文言は `strings.json`/`infoplist.json`/`servicesmenu.json` から `build-xcstrings.py` で生成。8 言語 (ja/en/de/es/fr/ko/pt-BR/zh-Hant、ja==キー)。`--check` missing 0。新規 UI 文言は `strings.json` に 8 言語で足す。
- 新規ファイルを作る Task は `xcodegen generate` して pbxproj をコミットに含める。
- コミット本文末尾は必ず:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- main/develop 直コミット禁止 (作業ブランチ `feature/dictionary-editor`)。バージョンは最後に **1.8.0 / ビルド 12** に上げる。

---

## 現状

- `suggestions-user.json` は Application Support/FolderArt に置かれる (`AppModel.userDictionaryURL`)。「ファイル > 提案辞書を開く…」(`revealUserDictionaryNotification` → `AppModel.revealUserDictionary()`) がファイルを用意して Finder で表示し、ユーザーが好きなエディタで手編集する。
- 保存されると `FileWatcher` (ディレクトリ + ファイル監視) が検知し `AppModel.reloadUserDictionary()` → 内容ハッシュが変われば提案エンジンを作り直す。
- `SuggestionEntry { keys: [String], symbol: String?, emoji: String? }`。読み込み・検証は `SuggestionDictionary.loadUser(at:)` / `loadUserSnapshot(at:)` / `normalizedUser(_:)`。
- 検証上限: `userMaxFileBytes` 1MB、`userMaxEntries` 1000、`userMaxKeysPerEntry` 50、`userMaxKeyLength` 64、`userMaxSymbolLength` 100、`userMaxEmojiLength` 8。`normalizedUser` はキーを NFKC + 小文字化 + 前後空白除去し、空キー・空項目・重複を整理する。エラーは `UserDictionaryError` (ローカライズ済み文言)。
- 記号選択の既存部品: `SymbolGridView(catalog: SymbolCatalog, selected: Binding<String?>)` (検索欄 + グリッド)。`SymbolCatalog.shared`。
- アプリは単一 `Window("FolderArt", id: "main")` シーン (WindowGroup 不使用)。`AppModel` は `AppDelegate` が所有 (`appDelegate.model`)。

## 設計

### コンポーネント

新規:
- `FolderArt/State/DictionaryEditorModel.swift` — `@MainActor final class DictionaryEditorModel: ObservableObject`。エディタの状態と操作。
- `FolderArt/Views/DictionaryEditorView.swift` — 専用ウィンドウの中身 (左リスト + 右詳細 + 保存バー)。
- 新規 UI 文言を `scripts/localization/strings.json` に追加 (8 言語)。

変更:
- `FolderArt/FolderArtApp.swift` — 2 つ目の `Window("提案辞書の編集", id: "dictionary-editor")` シーンを追加。「ファイル」メニューに「提案辞書を編集…」ボタン (`revealUserDictionary` の「開く…」は残す)。`@Environment(\.openWindow)` で開く。
- `FolderArt/AppModel.swift` — 変更は最小。エディタは `userDictionaryURL` を読み、保存後は FileWatcher 経由で自動再読込されるため、AppModel への新規メソッドは原則不要 (必要なら `userDictionaryURL` を公開のまま使う。既に `let userDictionaryURL: URL` は公開)。

### DictionaryEditorModel の責務とインターフェース

```swift
@MainActor
final class DictionaryEditorModel: ObservableObject {
    /// 編集中の項目。UI で編集しやすいよう識別子付きの参照型または id 付き struct にする。
    struct Row: Identifiable, Equatable {
        let id: UUID
        var keys: [String]       // 生の入力 (保存時に normalizedUser が正規化)
        var symbol: String?      // SF Symbols 名
        var emoji: String?
    }

    @Published private(set) var rows: [Row]
    @Published var selection: Row.ID?
    @Published private(set) var isDirty: Bool          // 未保存の変更があるか
    @Published var errorMessage: String?               // 保存時の検証エラー等 (アラート表示)
    @Published var pendingExternalChange: Bool         // 開いている間に外部でファイルが変わった

    let catalog: SymbolCatalog
    private let url: URL
    private var loadedContentHash: Data?               // 読み込んだ時点のファイル内容ハッシュ (外部変更検知用)

    init(url: URL, catalog: SymbolCatalog = .shared)

    /// 現在のファイルを読み直して rows を作る (開いた時 / 「読み直し」時)。
    /// ファイルが無ければ空。壊れている・上限超過なら errorMessage を出しつつ、
    /// 読める範囲 (デコードできた生 JSON) を可能な限り行にする。壊れて読めなければ空 + エラー。
    func reload()

    /// 行の追加・削除・キーの追加/削除・記号/絵文字の設定。すべて isDirty を立てる。
    func addRow()
    func deleteRows(_ ids: Set<Row.ID>)
    func addKey(_ raw: String, to id: Row.ID)
    func removeKey(_ key: String, from id: Row.ID)
    func setSymbol(_ name: String?, for id: Row.ID)
    func setEmoji(_ emoji: String?, for id: Row.ID)

    /// 保存: rows → [SuggestionEntry] → normalizedUser で検証。違反は errorMessage にして中止 (false)。
    /// 成功なら、外部変更 (現在のファイル内容ハッシュ != loadedContentHash) を確認し、
    /// 変わっていれば pendingExternalChange を立てて確認を促す (呼び出し側が上書き/読み直しを選ぶ)。
    /// 変わっていなければアトミックに書き出し、loadedContentHash を更新し isDirty=false にする。
    /// 上書き確定 (force) が来たら外部変更を無視して書き出す。
    @discardableResult func save(force: Bool = false) -> Bool
}
```

補足:
- `rows` → `[SuggestionEntry]` は素直な写像。`save` 内で `SuggestionDictionary.normalizedUser(entries)` を呼び、throw された `UserDictionaryError` の `errorDescription` を `errorMessage` に入れる。
- 書き出し JSON はエディタが `JSONEncoder`（`outputFormatting = [.prettyPrinted, .sortedKeys]` などは任意、人が後で手編集する前提で pretty 推奨）で生成。`normalizedUser` の結果 (正規化済みキー) を書く。保存後に `reload()` してもよい (正規化後の姿を表示)。
- 外部変更検知: `save` で書く直前に現在ファイルの内容ハッシュ (`SuggestionDictionary.loadUserSnapshot(at:).contentHash` あるいは同等) を計算し `loadedContentHash` と比較。異なれば `pendingExternalChange=true` を立てて `save` は false を返す (書かない)。UI が「上書き / 読み直し」を出す。「上書き」なら `save(force: true)`、「読み直し」なら `reload()`。

### 画面 (`DictionaryEditorView`)

- **左ペイン (幅 ~240)**: `List(rows, selection: $selection)`。各行は先頭キー (無ければ「(キー未設定)」) + 記号/絵文字の小プレビュー。下部ツールバー: 「＋」(addRow) 「−」(deleteRows(選択))。
- **右ペイン**: 選択行の詳細。選択が無ければプレースホルダ (「左で項目を選ぶか＋で追加」)。
  - **キー**: 現在のキーをチップ/行で列挙、各キーに削除ボタン。下に追加用 `TextField` + 「追加」(Enter でも可)。空文字は無視。1 項目 50 個・1 キー 64 字を超えそうなら追加を抑止 or 保存時にエラー。
  - **記号**: `SymbolGridView(catalog: catalog, selected: <Binding to row.symbol>)` を埋め込み + 「記号をクリア」。
  - **絵文字**: 1 文字 `TextField` (macOS 絵文字パレット Ctrl-Cmd-Space 対応) + 「クリア」。8 書記素以内。
- **下部バー**: 「保存」(isDirty のときだけ活性) 「閉じる」。`.alert` で検証エラー (`errorMessage`) と外部変更 (`pendingExternalChange`) の確認を出す。
- ウィンドウを閉じるときに isDirty なら破棄確認 (任意、実装が容易なら)。

### ウィンドウの仕組み (`FolderArtApp`)

```swift
Window("提案辞書の編集", id: "dictionary-editor") {
    DictionaryEditorView(model: DictionaryEditorModel(url: appDelegate.model.userDictionaryURL))
        .environmentObject(language)
}
.windowResizability(.contentMinSize)
.defaultSize(width: 720, height: 520)
```
「ファイル」メニューに `Button("提案辞書を編集…") { openWindow(id: "dictionary-editor") }` (`@Environment(\.openWindow) private var openWindow`)。既存の「提案辞書を開く…」(Finder 手編集) は残す。

注: `Window` シーンは単一インスタンス。エディタモデルはシーンで生成する (`@StateObject` にできないなら `DictionaryEditorView` 側で `@StateObject private var model` を持ち、`url`/`catalog` を渡して init する形にする)。**開くたびに現在のファイルを読み直す** (`onAppear` で `reload()`、または毎回新しいモデル)。SwiftUI の `Window` はモデルを保持しがちなので、`onAppear`/`onReceive` で `reload()` して最新化する。

### 保存と本体への反映

- 保存 → 親ディレクトリを (無ければ) 作成 → アトミック書き出し。
- **反映は明示通知で決定論的にする** (FileWatcher 頼みにしない): 保存成功後、エディタは新規の通知 (例 `AppModel.userDictionaryEditedNotification`) を post する。`ContentView`/`AppModel` はこれを受けて `reloadUserDictionary()` を呼び、必要なら `startDictionaryWatcher()` も呼ぶ。これで「ファイルが今まで無く FileWatcher がまだ監視していない」場合でも確実に本体が最新を読む。FileWatcher による自動再読込も従来どおり働くが、内容ハッシュのスキップにより二重に読んでも無害。
- エディタは AppModel の辞書状態を直接いじらない (疎結合)。渡すのは `userDictionaryURL` と保存後の通知のみ。

## バージョン

最後のタスクで `MARKETING_VERSION 1.8.0` / `CURRENT_PROJECT_VERSION 12`、README 日英併記に「提案辞書のアプリ内エディタ」を追記。

## テスト

`DictionaryEditorModelTests` (ロジック中心、UI は最小):
- 往復: 既存 json を `reload` → rows → `save` → ファイルが妥当な json になり、`loadUser` が同じ項目を返す。
- 追加/削除/キー操作で `isDirty` が立つ。
- 検証: 上限超過 (項目 1001・キー 51・キー 65 字・絵文字 9 字) や空キー・重複で `save` が false + `errorMessage`、ファイルは書き換わらない。空キーだけの項目は保存で捨てられる (normalizedUser の挙動)。
- 空ファイル/未作成から addRow → save でファイル生成。
- 外部変更: reload 後にファイルを別内容へ書き換え → `save` が `pendingExternalChange=true` で false (上書きしない)、`save(force: true)` で書ける、`reload` で最新を取り込む。
- 保存 json が本体の `SuggestionDictionary.loadUser` / `normalizedUser` と整合 (正規化済みキーで往復して不変)。

テスト用に `DictionaryEditorModel(url:)` へ一時ファイル URL を注入する。

## 非目標 (Non-goals)

- 同梱辞書 `suggestions.json` の編集 (アプリ同梱・不可)。
- リアルタイム同時編集や複数エディタウィンドウ。
- 記号/絵文字以外のオーバーレイ種別 (画像・文字) の辞書対応 (辞書は記号・絵文字のみ)。
- 提案のプレビュー (エディタ内で「このキーだとこう出る」を見せる) は今回やらない (将来候補)。
