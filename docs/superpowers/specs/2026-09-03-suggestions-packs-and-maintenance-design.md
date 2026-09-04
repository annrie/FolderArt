# FolderArt 第2段階: 自動提案・お気に入りパック・内部改善

作成日: 2026-09-03
対象バージョン: 1.3.0 (現行 1.2.1)
状態: 設計確定 (実装計画は別ファイル)
前提: 第1段階 spec `2026-09-02-overlay-sources-and-batch-design.md` (v1.2.0 で実装済み)

## 1. 範囲

第2段階で扱うのは次の 3 つ。

| 記号 | 内容 |
|------|------|
| A | フォルダ名からの自動提案 (記号・絵文字・文字・お気に入りの候補をタブの上に最大 3 つ) |
| C | お気に入りパックの書き出しと読み込み (`.folderartpack`、画像を内包する単一 JSON) |
| D | 第1段階からの持ち越し: 移動したフォルダの履歴の同一性、一括適用の履歴書き込みを 1 回に、`backups/` と `.corrupt-*` の掃除 |

加えて README のメイン画像を 1.3.0 の画面に差し替える (§8)。

第3段階以降に送るもの: フォルダの中身からの生成 (B)、お気に入りの一部だけの書き出し、提案辞書のユーザー編集、多言語化、フォント・太さの UI。

## 2. 決定事項 (対話で確定)

- 提案は **チップで見せるだけ**。自動では適用しない。
- 提案の元になるフォルダは **選択中の行、無ければ最後に追加した行**。
- パックは **単一ファイル `.folderartpack` (JSON、画像は Base64 内包)**。
- 読み込み時の重複は **全部追加し、名前が重なれば「名前 2」**。オーバーレイと設定が完全に同一なら追加しない。
- 入り口は **お気に入りの帯の「…」メニュー + メニューバー「ファイル」+ `.folderartpack` のダブルクリック**。書き出す対象はお気に入り全部。
- 新しいウィンドウやシートは増やさない (第1段階と同じ方針)。

## 3. 自動提案 (A)

### 3.1 SuggestionEngine

```swift
struct Suggestion: Equatable, Identifiable {
    enum Kind { case symbol(String), emoji(String), text(String), preset(Preset) }
    let kind: Kind
    let reason: String        // ツールチップ用 (例: 「"photo" に一致」)
    var id: String            // kind から導出
}

struct SuggestionEngine {
    init(dictionary: SuggestionDictionary, catalog: SymbolCatalog)
    func suggest(for folderName: String, presets: [Preset]) -> [Suggestion]   // 最大 3
}
```

知識は 3 層。優先順は **お気に入り → 辞書 → SF Symbols の検索語 → 規則** (お気に入りは自分で作った見た目なので最優先)。

1. **お気に入り**: `preset.name` がフォルダ名に含まれる (大文字小文字と全角半角を無視) お気に入りを候補にする。
2. **同梱辞書 `Resources/suggestions.json`**: `[{ "keys": ["写真", "photo", "photos", "pictures"], "symbol": "photo.fill", "emoji": "📷" }, ...]` を約 150 語、日英で用意する。記号名は `SymbolCatalog.names` に含まれるものだけを使う (制限付き記号を辞書に入れない。テストで検証)。
3. **SF Symbols の検索語**: 辞書に無い英単語を `SymbolCatalog` の検索語索引 (`symbol_search.plist`) で引き、最初の一致を記号候補にする。
4. **規則**: 4 桁の数字 (`2025`) や 2 文字以内の英数字 (`A`, `Q3`) は文字候補にする。

### 3.2 語の切り出し

- 英数字: 空白・`_`・`-`・`.`・`(`・`)`・camelCase の境界で分割し、小文字化して辞書の `keys` と完全一致。
- 日本語: 分かち書きしないので、辞書の `keys` (日本語) をフォルダ名の部分文字列として探す。長い語から先に当てる。誤爆を避けるため辞書の日本語キーは **2 文字以上** とし、「書」「金」のような一般的な 1 文字は入れない。
- 正規化: フォルダ名と辞書キーの両方を NFKC で正規化する (全角英数字 → 半角、半角カナ → 全角カナ、大文字 → 小文字)。ひらがな・カタカナの相互変換は行わない (辞書側に両方を書く)。
- テストに「無関係な語の中に短いキーが含まれるケース」の否定例を入れる。

### 3.3 候補の組み立て

- 記号 1、絵文字 1、文字 1 を上限に最大 3 つ。お気に入り候補は記号枠を使う (最優先)。
- 同じ記号・絵文字・文字は重複させない。
- 何も当たらなければ空配列を返す。帯 (§3.4) は高さを保ったまま空にする (レイアウトを動かさない)。

### 3.4 画面

- `OverlayPickerView` のタブの上に `SuggestionStripView` (高さ 36pt 固定。候補が無いときはチップを出さず空のまま高さを保つ) を置く。「提案:」ラベルの後にチップ。チップの見た目は `PresetStripView` のチップと同じ (サムネイルは `OverlayRenderer` で 128px を 1 回描いてキャッシュ)。
- クリックの挙動: 記号 → 記号タブに切り替えて `symbolName` を設定。絵文字 → 絵文字タブ + `emoji`。文字 → 文字タブ + `text`。お気に入り → `applyPreset` (設定まで復元)。記号・絵文字・文字の候補では色などの設定は変えない。
- 対象フォルダは `FolderSelection` から導出: 選択があれば選択中の行のうちリスト順で最後のもの、選択が無ければ `folders.last`。`AppModel` が `folders.$folders` と `$selectedIDs` を購読して `suggestions` を更新する。計算は同期・純関数なのでデバウンス不要。
- 適用中 (`isApplying`) はチップを無効にする。

### 3.5 テスト

- 辞書ヒット (日英)、日本語の部分一致、年号と短い英数字の規則、上限 3 と種類の重複なし、お気に入りの取り込みと最優先、何も当たらないとき空。
- 辞書の全 `symbol` が `SymbolCatalog.names` に含まれる (制限付き記号が混ざっていない)。

## 4. パック (C)

### 4.1 ファイル形式

拡張子 `.folderartpack`、UTType `com.example.folderart.pack` (`public.json` に準拠)。

```json
{
  "format": 1,
  "app": "FolderArt",
  "appVersion": "1.3.0",
  "exportedAt": "2026-09-03T12:00:00Z",
  "presets": [
    { "name": "写真", "overlay": { "symbol": { "name": "photo.fill" } }, "settings": { ... } },
    { "name": "ロゴ", "overlay": { "image": { "assetID": "..." } }, "settings": { ... },
      "image": "<Base64 PNG>" }
  ]
}
```

- `overlay` と `settings` は `Preset` の JSON をそのまま使う。`id` と `createdAt` は書き出さない (受け取り側で振り直す)。
- `.image(assetID:)` の項目だけ `AssetStore` の PNG を Base64 で `image` に添える。`assetID` の値は読み込み側で無視する。
- 上限: 1 パック 200 件。読み込み時、画像は `AssetStore.store(_:)` を通すので 512px に再縮小される。

### 4.2 部品

```swift
struct PackEntry: Codable { var name: String; var overlay: Overlay; var settings: CompositionSettings; var image: Data? }
struct Pack: Codable { var format: Int; var app: String; var appVersion: String; var exportedAt: Date; var presets: [PackEntry] }

enum PackWriter { static func write(_ presets: [Preset], assets: AssetStore) throws -> Data }
enum PackReader { static func read(_ data: Data) throws -> Pack }           // format != 1 や壊れた JSON は throw
struct ImportSummary: Equatable { var added: Int; var skippedIdentical: Int }
enum PresetImporter {
    static func importPack(_ pack: Pack, into store: PresetStore, assets: AssetStore) throws -> ImportSummary
}
```

- `PresetImporter`: 各項目について、画像があれば `AssetStore.store(_:)` で新しい ID に複製して `overlay = .image(assetID: newID)` に置き換える。重複判定は **既存のお気に入り + このパックで既に追加を決めた項目** に対して行い、`overlay` と `settings` が完全に等しいものは `skippedIdentical` に数えて追加しない (パック内の重複も 1 つにまとまる)。名前が重なれば `PresetStore.defaultName` と同じ規則で「名前 2」(こちらも既存 + 追加予定の名前に対して)。追加は `PresetStore.addAll(_:)` で **1 回の保存** にまとめる (途中で失敗したら 1 件も追加しない。複製した PNG は次回起動の掃除に任せず、その場で削除する)。
- 書き出しのファイル名の既定値: `FolderArt-お気に入り-<yyyyMMdd>.folderartpack`。

### 4.3 入り口

- `PresetStripView` 右端に「…」メニュー (`Menu`): 「パックを書き出す…」「パックを読み込む…」。お気に入りが 0 件なら書き出しは無効。
- メニューバー「ファイル」に同じ 2 項目 (`FolderArtApp` の `.commands`)。
- `.folderartpack` のダブルクリック: `project.yml` の `info.properties` に次を宣言し (XcodeGen が `Info.plist` に出力)、`ContentView` の `onOpenURL` で `AppModel.importPack(url:)` を呼ぶ。

```yaml
CFBundleDocumentTypes:
  - CFBundleTypeName: FolderArt Preset Pack
    CFBundleTypeRole: Viewer
    LSHandlerRank: Owner
    LSItemContentTypes: [com.example.folderart.pack]
UTExportedTypeDeclarations:
  - UTTypeIdentifier: com.example.folderart.pack
    UTTypeDescription: FolderArt Preset Pack
    UTTypeConformsTo: [public.json]
    UTTypeTagSpecification:
      public.filename-extension: [folderartpack]
```
- `AppModel.exportPack()` は `NSSavePanel`、`importPack(url:)` は読み込み → 概要をアラート「3 件追加しました (1 件は同じものがあるため省略)」。適用中は両方とも拒否。
- サンドボックス: パネルや `onOpenURL` から受け取った URL は `startAccessingSecurityScopedResource()` で囲んで読み書きし、`defer` で閉じる (パネル由来の URL は権限付きで渡されるが、`onOpenURL` 経由は明示的に開く)。

### 4.4 失敗の扱い

| 事象 | 扱い |
|------|------|
| `format` が未対応 | 「このパックは新しいバージョンの FolderArt で作られています」アラート。何も追加しない |
| JSON が壊れている | 「パックを読み込めません」アラート |
| `overlay` が `.image` なのに `image` が無い、PNG として復号できない | その項目ではなくパック全体を拒否 (一括で入るか入らないか)。検証は PNG を 1 枚も保存する前に全項目に対して行う |
| 200 件超 | 拒否してアラート |
| 保存に失敗 | 追加せず、複製した PNG を削除してアラート |
| 書き出しの保存に失敗 | アラート |

### 4.5 テスト

- `PackWriter` → `PackReader` の往復 (記号・文字・画像入り)。画像の Base64 が `AssetStore` の PNG と一致。
- `PresetImporter`: 名前の付け直し、完全一致の省略、画像の再複製と ID の振り直し、`format: 2` の拒否、壊れた JSON の拒否、201 件の拒否、保存失敗時に PNG が残らない。
- `PresetStore.addAll` が 1 回の保存で全件入る (途中失敗で 0 件)。

## 5. 持ち越し (D)

### 5.1 移動したフォルダの履歴の同一性

- `IconTask` に `fileID: String?` を追加。値は `<volumeUUID>:<inode>` の形で、`URLResourceKey.volumeUUIDStringKey` と `FileManager.attributesOfItem(atPath:)[.systemFileNumber]` (inode 番号) から作る (どちらかが取れなければ `nil`)。`fileResourceIdentifierKey` は使わない: inode に加えてマウント時に決まるファイルシステム ID を含み、再起動や外付けボリュームの抜き差しをまたぐと値が変わるため (Apple の文書でも "not persistent across system restarts")。`decodeIfPresent` で読むので既存の v2 行は `nil`。版数 (`currentVersion = 2`) は変えない。
- 効く範囲: 同一ボリューム内の名前変更・移動。コピーや別ボリュームへの移動、削除して作り直したフォルダは別物として扱う (path 比較に落ちる)。値には作成日時 (改名・移動で不変) も含め、削除後に inode が再利用されても別物になるようにする。**行と現在のフォルダの両方に `fileID` があるときは `fileID` だけで判定する** (path が同じでも別物: 移動した後に同じ場所へ作った別のフォルダ)。
- 適用時に `fileID` を取得して記録する。取得できなければ `nil`。
- `HistoryStore.upsert` は「`folderPath` が同じ」または「`fileID` が同じ (nil 同士は不一致)」の行を置き換える。置き換え時は既存行の `backupPath` を引き継ぐ (第1段階の規則どおり)。
- バックアップの鍵は `fileID` (取れなければ適用時の path) の base64。path だけを鍵にすると、フォルダを移動した後に同じ場所へ作った別のフォルダが古いバックアップを「元のアイコン」として拾ってしまう。**参照は常に行の `backupPath` を正とする** (鍵の形が変わっても既存の行のリセットには影響しない)。リセット後のバックアップ削除 (`removeBackup`) も現在の URL から鍵を導くのではなく `task.backupPath` の親ディレクトリを消す。これで移動後も掃除 (§5.3) と整合する。
- テスト: 同じ `fileID` で path が違う行を upsert すると 1 行に置き換わる。`fileID` が nil 同士の別 path は 2 行のまま。

### 5.2 一括適用の履歴の保存

- 履歴はフォルダごとに保存する (第 1 段階と同じ)。アイコンを変えたフォルダの行が、保存前の状態で残ることはない。
- 保存に失敗したフォルダはそのフォルダだけアイコンを戻し、理由「履歴の保存に失敗」で失敗にする (他のフォルダは続行)。戻せなかったときは、そのフォルダのために作ったバックアップを残す。
- 同じ実体のフォルダが別の path (実パスとシンボリックリンクなど) で 2 回来たら、2 回目は飛ばす (`fileID` で判定)。
- 当初の「最後に 1 回だけ保存 + 途中経過の控え (history-pending.json)」は、控えの回収まわりに穴が続いたため 2026-09-05 に撤回した。

### 5.3 掃除

- `MaintenanceSweep` を起動時に 1 回実行。候補の列挙 (`backupCandidates`) と隔離ファイルの削除 (`removeOldCorruptFiles`) はメインの外、バックアップの片付け (`removeBackupDirectories`) は `AppModel` がメインアクターで最新の履歴と照合してから行う (列挙中に適用が既存のバックアップを再利用して履歴に載せることがあるため。適用中なら見送る)。
  1. 履歴のどの行の `backupPath` にも含まれない `backups/<key>/` (ディレクトリのみ) を **ゴミ箱へ移す** (完全削除はしない。誤って片付けても元アイコンを取り戻せる)。行わない条件: 履歴の読み込みに失敗している (`loadError != nil`)、`history.json.corrupt-*` の隔離ファイルが残っている (壊れた履歴を退避した直後に書かれる 1 行だけの `history.json` を「全部」と信じない)、起動時刻以降に作られた (今のセッションのもの)、作成日時が取れない。
  2. `<name>.json.corrupt-yyyyMMdd-HHmmss` (CodableStore の隔離ファイルの形だけ。他の ".corrupt-" は触らない) のうち、更新日時が 30 日より古いものを削除。
- 失敗は無視 (次回また試す)。片付けた件数は os.Logger に残す (0 件なら出さない)。UI には出さない。
- テスト: 参照あり/なしのバックアップ、29 日と 31 日前の `.corrupt-*`、`loadError` 時にバックアップを消さない、起動後に作られたものを消さない、列挙後に参照が付いた候補を消さない、`history.json` の隔離ファイルがある間は消さない、ゴミ箱へ移る、ディレクトリ以外は触らない、ルートは残る、ディレクトリが無くても 0 件で返る。

## 6. 画面と状態のまとめ

- 新規: `Services/SuggestionEngine.swift`、`Services/SuggestionDictionary.swift` (JSON の読み込み)、`Resources/suggestions.json`、`Views/SuggestionStripView.swift`、`Services/PackWriter.swift`、`Services/PackReader.swift`、`Services/PresetImporter.swift`、`Services/MaintenanceSweep.swift`。
- 変更: `AppModel` (`suggestions`、`applySuggestion(_:)`、`exportPack()`、`importPack(url:)`、起動時の掃除)、`FolderArtApp` (`.commands`、`onOpenURL` は `ContentView`)、`OverlayPickerView` (提案の帯)、`PresetStripView` (「…」メニュー)、`PresetStore` (`addAll`)、`HistoryStore` (`upsertAll`、`fileID` 判定)、`IconTask` (`fileID`)、`ApplyCoordinator` (最後に 1 回保存)、`project.yml` / `Info.plist` (UTType、1.3.0 / ビルド 6)。
- 文言はすべて `Text("…")` / `String(localized:)`。

## 7. エラー処理

| 事象 | 扱い |
|------|------|
| 提案辞書が読めない | 規則と検索語だけで動く。ユーザーには見せない |
| パックの読み書き失敗 | §4.4 のとおりアラート。部分的な取り込みはしない |
| 一括適用の最終保存失敗 | 全件巻き戻し + 全件失敗として報告 |
| 掃除の失敗 | 無視 |

## 8. README のメイン画像

- README の `<img src="https://github.com/user-attachments/...">` (1.0.1 の画面) を、リポジトリ内 `docs/images/main.png` への相対参照に置き換える。
- 画像は 1.3.0 の実機画面 (フォルダ 3 件、記号タブ、提案の帯にチップ 3 つ、お気に入りのチップ 2 つ、プレビュー表示) を Retina 2x で撮り、幅 1520px 程度で保存する。撮影は第1段階と同じ自動化 (CGWindowID 指定の `screencapture`) で行う。
- 日英併記の機能一覧に「自動提案」「お気に入りパック」を追記する。

## 9. テスト方針の要約

新規テストは §3.5、§4.5、§5 の各項目。既存 102 件は維持。UI は実機で撮って確認 (提案チップのクリック、「…」メニューからの書き出しと読み込み、ダブルクリックでの読み込み、同一名の付け直し)。

## 10. 影響を受ける既存ファイル

| ファイル | 変更 |
|----------|------|
| `Models/IconTask.swift` | `fileID: String?` |
| `Stores/HistoryStore.swift` | `upsertAll`、`fileID` による置き換え |
| `Stores/PresetStore.swift` | `addAll` |
| `Services/ApplyCoordinator.swift` | 最後に 1 回保存、全件巻き戻し、バックアップの非同期化 |
| `AppModel.swift` | 提案・パック・掃除の呼び出し |
| `FolderArtApp.swift` | ファイルメニュー |
| `ContentView.swift` | `onOpenURL`、提案の帯 |
| `Views/OverlayPickerView.swift` | 提案の帯を上に配置 |
| `Views/PresetStripView.swift` | 「…」メニュー |
| `project.yml`, `Info.plist` | UTType 宣言、1.3.0 / ビルド 6、`Resources/suggestions.json` |
| `README.md` | 画像差し替え、機能一覧 |
