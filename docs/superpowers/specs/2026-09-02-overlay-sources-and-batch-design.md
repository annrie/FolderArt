# FolderArt 第1段階: オーバーレイ供給源の拡張・お気に入り・一括適用

作成日: 2026-09-02
対象バージョン: 1.1.0 (現行 1.0.1)
状態: 設計確定 (実装計画は別ファイル)

## 1. 背景と目的

FolderArt は「フォルダアイコンに画像を重ねる」だけの単機能アプリで、その単純さが支持されている。
機能を足しても「単純なまま使いやすくする」方向を守る。

ロードマップは3段階に分ける。本 spec は第1段階のみを扱う。

| 段階 | 内容 |
|------|------|
| 1 (本 spec) | 供給源4種 (画像 / 記号 / 絵文字 / 文字)、お気に入り、複数フォルダへの一括適用、hover プレビュー |
| 2 | フォルダ名からの自動提案、フォルダの中身からの生成、お気に入りパックの書き出しと読み込み |
| 3 | 多言語化 (String Catalog)、文字系オーバーレイのフォント・太さの開放 |

## 2. 決定事項 (対話で確定)

- 一括適用は「同じオーバーレイを全フォルダに貼る」方式。フォルダごとに別々のオーバーレイを持つ表形式は採らない。ただしフォルダリストで行を選択すれば「選択したフォルダだけに適用」できるので、全部に貼ったあと一部だけを別のものに貼り直せる (再適用は上書きになる)。
- 記号・絵文字・文字の見た目は第1段階では「色」ひとつだけ選べる。フォントはシステムの丸ゴシック太字に固定。ただしモデルにはフォント名と太さを初期値付きで持たせ、第3段階で UI を足すだけで開放できるようにする。
- お気に入りは「オーバーレイ + 合成設定」を一組で保存する (見た目まるごと)。画像のお気に入りは元ファイルを参照せず、アプリ領域に 512px の PNG として複製する。
- 画面は現行の縦の流れ (選ぶ → 整える → 確かめる → 適用) を保つ A 案。新しいウィンドウやシートは増やさない。
- ドラッグ&ドロップは維持し、複数フォルダの一括ドロップ、ウィンドウ任意位置への画像ドロップに広げる。

## 3. SF Symbols のライセンス上の扱い

根拠: Xcode and Apple SDKs Agreement §2.10 "System-Provided Images"、Human Interface Guidelines "SF Symbols"。

- SF Symbols は System-Provided Images として、Apple 製品上で動くアプリの開発のためにライセンスされる。FolderArt は macOS 上で実行時に `NSImage(systemSymbolName:)` で描画するため、この枠内。
- 禁止事項は「app icon、ロゴ、その他の商標的用途」への組み込み。ユーザーが自分のフォルダに貼るアイコンは FolderArt のアプリアイコンでもロゴでもない。
- Apple 製品や機能を表す記号 (Info バッジ付き) は「表示はできるが改変できない」。FolderArt は色変更と合成を行うため、これらはカタログから除外する。
- 記号の画像ファイルをアプリに同梱しない。SF Symbols アプリ (デザインツール) の EULA は書き出し物に対してより厳しい制限を課すため、実行時描画に限定する。

除外対象の一覧は macOS 自身が持つ:

```
/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_restrictions.strings
```

macOS 15 時点で 525 件。起動時にこれを読んで除外する。読めない場合は同梱の固定除外リストで fallback する (外し漏れの方がリスクが高いため)。

## 4. データモデル

すべて `Codable`, `Equatable`, `Sendable`。

```swift
enum Overlay: Codable, Equatable, Sendable {
    case image(assetID: UUID)      // Application Support/FolderArt/assets/<id>.png
    case symbol(name: String)      // SF Symbols 名
    case emoji(String)
    case text(String)
    case legacyImage(name: String) // v1 履歴の移行専用。再適用不可 (§4.1)
}

struct CompositionSettings: Codable, Equatable, Sendable {
    var position: IconPosition       // .center / .badge (既存)
    var scale: Double                // 0.2 ... 1.0 (既存)
    var opacity: Double              // 0.1 ... 1.0 (既存)
    var verticalOffset: Double       // -0.4 ... 0.4 (既存)
    var clipToFolderShape: Bool      // 既存 (UI 表示名を「フォルダ形に切り抜く」に正す)
    var tintColor: CodableColor      // 新規。記号・文字に適用。初期値は白
    var fontName: String?            // 新規。nil = システム丸ゴシック。第3段階で UI 開放
    var fontWeight: FontWeightValue  // 新規。初期値 .bold。第3段階で UI 開放
}

struct Preset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var overlay: Overlay
    var settings: CompositionSettings
    let createdAt: Date
}

struct IconTask: Codable, Identifiable, Equatable, Sendable {
    static let currentVersion = 2
    let version: Int
    let id: UUID
    let folderPath: String
    let bookmark: Data
    let backupPath: String?
    let overlay: Overlay
    let settings: CompositionSettings
    let appliedAt: Date
}
```

`CodableColor` は RGBA の Double 4つを持つ小さな構造体で、`NSColor` との相互変換を提供する。

### 4.1 履歴ファイルの移行

現行 `history.json` の `IconTask` は `version` 欄がなく、設定が5つの平置き欄 (`position`, `scale`, `opacity`, `verticalOffset`, `clipToFolderShape`)、オーバーレイは `imageName: String` のみ。

- デコード時に `version` が無ければ v1 として読む。
- v1 の `imageName` は復元不能なので `overlay = .text("")` ではなく、専用の `Overlay.legacyImage(name:)` ケースを設け、履歴表示では名前だけ出し、再適用は不可とする。
- v1 の平置き設定は `CompositionSettings` に詰め替え、新規欄は初期値で埋める。
- 読み込み後は v2 として保存し直す。

## 5. 描画と合成

### 5.1 OverlayRenderer (新規)

```swift
enum OverlayRenderer {
    /// 透明背景の正方形 (side x side) に描画する。文字系が空文字なら nil。
    static func render(_ overlay: Overlay, settings: CompositionSettings,
                       side: CGFloat, assets: AssetStore) -> NSImage?
}
```

- `.image`: `AssetStore` から PNG を読み、アスペクト維持で正方形に収める。
- `.symbol`: `NSImage(systemSymbolName:accessibilityDescription:)` に `NSImage.SymbolConfiguration(pointSize:weight:)` を適用し、`tintColor` で塗る。
- `.emoji` / `.text`: `NSAttributedString` (フォント: `fontName ?? .systemFont(ofSize:weight:)` の rounded design、色: `tintColor`。絵文字は色を無視) を描画。1行、はみ出す場合は縮小して収める。
- 出力は常に正方形なので、既存の `calculateRect(for:in:settings:)` を4種類で共用する。

### 5.2 IconComposer (既存を変更)

- 元アイコンを `NSWorkspace.shared.icon(forFile:)` から **標準フォルダアイコン** (`NSWorkspace.shared.icon(for: .folder)`) に変える。加工済みフォルダへの再適用で重ね塗りになる問題を解消する。
- `compose(base:overlay:settings:) -> NSImage` に変え、ファイルパス依存をなくす。
- `nonisolated` にし、メインスレッド外で呼べるようにする。
- 出力は 512px 単一表現のまま (現行踏襲)。

### 5.3 SymbolCatalog (新規)

```swift
struct SymbolCatalog {
    let names: [String]                        // 制限付きを除いた全記号名
    func search(_ query: String) -> [String]   // 名前と検索語の部分一致
    static func load() -> SymbolCatalog        // CoreGlyphs.bundle から。失敗時は同梱 fallback
}
```

- `name_availability.plist` から実行中の macOS で使える記号名を取り、`symbol_restrictions.strings` の名前を除く。
- 検索語は `symbol_search.plist` を使う。
- fallback は `Resources/restricted-symbols.txt` (同梱、`symbol_restrictions.strings` から生成) と、`NSImage(systemSymbolName:)` が nil を返さないことでの存在確認。

## 6. 一括適用

### 6.1 ApplyCoordinator (新規、ContentViewModel から分離)

```swift
struct ApplyOutcome { let succeeded: [URL]; let failed: [(URL, Error)] }

actor ApplyCoordinator {
    func apply(overlay: Overlay, settings: CompositionSettings,
               to folders: [URL], progress: @Sendable (Int, Int) -> Void) async -> ApplyOutcome
}
```

- レンダラーの出力は1回だけ作り、全フォルダに使い回す。
- 各フォルダについて順に: バックアップ → 合成 → `NSWorkspace.setIcon` → ブックマーク作成 → 履歴に追加 (同じ `folderPath` の行は置き換え)。
- 1件の失敗で止めない。成功分は取り消さない。
- `setfile` の `Process` 起動は削除する。

### 6.2 UI 上の振る舞い

- 適用先は、リストで行が選択されていればその行、選択が無ければ全行。
- 適用ボタンの文言は「N フォルダに適用」、選択中は「選択した N フォルダに適用」。
- 適用後もリストと選択はそのまま残す。一部を貼り直す操作の起点になる。
- 進捗はボタン脇に「2 / 5」の小さな表示。専用シートは作らない。
- 全件成功: 今どおり静かに終了。
- 一部失敗: 「2 件成功、1 件失敗」と、失敗したフォルダ名と理由の一覧をアラートで表示。

## 7. 保存

### 7.1 CodableStore<T> (新規、HistoryStore の読み書きを抽出)

```swift
final class CodableStore<T: Codable> {
    init(fileURL: URL)
    func load() throws -> T?
    func save(_ value: T) throws
}
```

- 失敗は握りつぶさず `throws` で返す。
- `HistoryStore` と `PresetStore` がこれを使う。

### 7.2 AssetStore (新規)

- `Application Support/FolderArt/assets/<uuid>.png` に画像を 512px に縮めて保存する。
- お気に入り保存時と、画像タブで画像を選んだ時 (履歴からの再適用のため) に複製する。
- 参照されなくなった PNG は、お気に入りまたは履歴の削除時に消す。両方から参照される可能性があるので、削除前に参照カウントを確認する。

### 7.3 PresetStore (新規)

- `Application Support/FolderArt/presets.json` に `[Preset]` を保存。
- `add(from overlay:settings:name:)`, `rename`, `remove`, `all`。
- 画像プリセットの追加は `AssetStore` への複製を伴う。

### 7.4 ファイル配置

```
~/Library/Application Support/FolderArt/
├── history.json      (v2)
├── presets.json
├── assets/<uuid>.png
└── backups/<base64-path>/original.png   (既存)
```

## 8. 画面

ウィンドウ: 760 x 720、リサイズ可 (現行 600 x 700 固定から変更)。縦の流れは現行どおり。

```
┌ ツールバー: [履歴] ─────────────────────────────┐
│ ┌ FolderListView ─┐ ┌ OverlayPickerView ──────┐ │
│ │ フォルダ (3)     │ │ [画像][記号][絵文字][文字] │ │
│ │ 2024 案件      × │ │ (タブの中身)             │ │
│ │ 2025 案件      × │ │                          │ │
│ │ ＋ 追加 / ドロップ│ │                          │ │
│ └─────────────────┘ └──────────────────────────┘ │
│ ┌ PresetStripView: お気に入り [★][📷][26] … [＋] ┐ │
│ ┌ ControlsView ───────────┐ ┌ PreviewView ─────┐ │
│ │ 配置 / 大きさ / 透明度   │ │   (128px)         │ │
│ │ 上下位置 / 色            │ │                   │ │
│ └─────────────────────────┘ └───────────────────┘ │
│              3 フォルダに適用   [リセット] [適用]   │
└──────────────────────────────────────────────────┘
```

### 8.1 各ビュー

- **FolderListView** (新規): `[URL]` を表示。リスト全体がドロップ先で、複数フォルダを一括追加。「＋」で `NSOpenPanel` (`allowsMultipleSelection = true`)。行の「×」で除外。重複は追加しない。行は複数選択可 (クリックで選択、Cmd+クリックで追加、Esc で解除)。選択は適用先の絞り込みにのみ使い、選択が無ければ全行が対象。
- **OverlayPickerView** (新規): `Picker(.segmented)` で4タブ。
  - 画像: 既存 `DropZoneView(mode: .image)` をそのまま配置。
  - 記号: 検索欄 + `LazyVGrid` (8列)。`SymbolCatalog.search` の結果を表示。選択中は強調。
  - 絵文字: 1文字の入力欄 + 「絵文字パレット」ボタン (`NSApp.orderFrontCharacterPalette(nil)`)。
  - 文字: 1行の入力欄 (最大 8 文字を目安、超えたら描画側で縮小)。
  - 入力を持つタブで値が空なら、プレビューを出さず適用ボタンを無効にする。
- **PresetStripView** (新規): 横スクロールのチップ列。チップはサムネイル (64px、`OverlayRenderer` の出力を標準フォルダに合成したもの)。クリックでオーバーレイと設定を一度に復元 (該当タブへ切り替え)。右クリックで「名前を変更」「削除」。右端の「＋」で現在の見た目を保存 (名前は初期値を自動生成し、後から変更可)。お気に入りが 0 件のときは「＋」と短い説明だけを出す。
- **ControlsView** (既存): 「色」の行を `ColorPicker` で追加 (画像タブでは無効表示)。「フルイメージ」チェックの表示名を「フォルダ形に切り抜く」に改め、内部名 `clipToFolderShape` と一致させる。
- **PreviewView** (新規に切り出し): 128px 表示。`onHover` で、元の位置を動かさずに 256px の拡大版と 16 / 32 / 64 / 128 px の実寸列を `overlay` + `zIndex` で上に重ねる。ポインタが外れたら消す。アニメーションは 0.15 秒。
- **ドロップの振り分け**: ウィンドウ全体で `.fileURL` を受け、フォルダは `FolderListView` へ、画像は画像タブへ切り替えて渡す。混在していれば両方に振り分ける。既存の `DropReceiverNSView.fileURL(from:)` は全件を返すように変える。

### 8.2 状態の分割

`ContentViewModel` を次の3つに分け、`ContentView` はこれらを組み合わせる。

- `FolderSelection` (`ObservableObject`): `folders: [URL]`、`selectedIDs: Set<URL>`、追加・削除・重複除去。`targets: [URL]` は選択があれば選択分、無ければ全件を返す。
- `OverlayState` (`ObservableObject`): `overlay: Overlay?`、`settings`、`activeTab`、`previewImage`。プレビュー更新は 100ms のデバウンス付きでメインで 1 枚だけ描く。
- `ApplyCoordinator` (actor): §6.1。

### 8.3 文言

新規の文言はすべて `LocalizedStringKey` または `String(localized:)` で書く。第3段階の String Catalog 導入の下準備。

## 9. エラー処理

| 事象 | 扱い |
|------|------|
| 一括適用の一部失敗 | 件数と、失敗フォルダ名 + 理由の一覧をアラート。成功分は保持 |
| バックアップ失敗 | そのフォルダの適用を中止し、失敗として集計 |
| お気に入り・履歴の読み書き失敗 | アラートで表示。握りつぶさない |
| 画像の複製失敗 (AssetStore) | お気に入り保存を中止しアラート |
| SymbolCatalog 読み込み失敗 | 同梱 fallback で動作。ユーザーには見せない |
| ブックマーク作成失敗 | 適用自体は成功扱い。履歴からのリセットが不可になる旨を履歴行に表示 |

## 10. テスト

既存の XCTest 構成に合わせる。

- **OverlayRendererTests**: 4種類が非 nil の正方形を返す。`.emoji("")` / `.text("")` は nil。`.symbol` と `.text` の中央付近ピクセルが `tintColor` に一致。
- **IconComposerTests**: 既存の geometry テストを維持。標準フォルダアイコンを使うため、同じ入力で2回合成した結果のピクセルが一致する (重ね塗りの回帰防止)。
- **SymbolCatalogTests**: `symbol_restrictions.strings` の名前が `names` に含まれない。`search("folder")` が `folder` を含む名前を返す。fallback リストが空でない。
- **FolderSelectionTests**: 選択なしで `targets` が全件、選択ありで選択分のみ。重複追加されない。
- **ApplyCoordinatorTests**: 3 フォルダのうち 1 つを書き込み不可にし、`succeeded.count == 2`, `failed.count == 1`。成功分の履歴が残る。同じフォルダへの再適用で履歴の行数が増えない。
- **CodableStoreTests**: 保存と復元。壊れた JSON で `throws`。
- **PresetStoreTests / AssetStoreTests**: 画像プリセット追加で PNG が作られる。削除で PNG が消える。履歴からも参照されている PNG は消えない。
- **IconTaskMigrationTests**: v1 形式の JSON が読め、`version == 2` で保存し直される。
- **FolderIconManagerTests**: `testBackupReturnsPath` を現行実装 (Icon\r が無ければ nil) に合わせて修正。

## 11. 第1段階で扱わないもの

- フォルダ名からの自動提案、中身からの生成 (第2段階)
- お気に入りパックの書き出しと読み込み (第2段階)
- 多言語化、フォント・太さの UI (第3段階)
- 512px 以外のアイコン表現の生成
- Finder 拡張、クイックアクション

## 12. 影響を受ける既存ファイル

| ファイル | 変更 |
|----------|------|
| `Services/IconComposer.swift` | `CompositionSettings` 拡張と Codable 化、`compose` の署名変更、標準フォルダアイコン化、nonisolated |
| `Services/FolderIconManager.swift` | `setfile` 呼び出し削除 |
| `Models/IconTask.swift` | v2 形式へ、移行デコード |
| `Stores/HistoryStore.swift` | `CodableStore` 利用、同一パスの置き換え、エラー伝播 |
| `ContentViewModel.swift` | 3 つに分割 |
| `ContentView.swift` | 新ビューの組み立て、ウィンドウ全体のドロップ振り分け |
| `Views/DropZoneView.swift` | 複数 URL の受け取り |
| `Views/ControlsView.swift` | 色の行、表示名修正 |
| `Views/HistoryView.swift` | `IconTask` v2 対応、legacy 行の表示 |
| `FolderArtApp.swift` | ウィンドウサイズとリサイズ可 |
| `project.yml` | バージョン 1.1.0、`Resources/restricted-symbols.txt` の追加 |
| `FolderArtTests/*` | §10 |
