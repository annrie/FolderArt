# FolderArt 第4段階: 上下位置の既定値、お気に入りの一部書き出し、ユーザー辞書、文言チェックの実物照合

作成日: 2026-09-06
対象バージョン: 1.5.0 (現行 1.4.0、ビルド 7 → 8)
状態: 設計確定 (実装計画は別ファイル)
前提: 第3段階 spec `2026-09-05-fonts-i18n-contents-design.md` (v1.4.0 で実装済み、PR #4)

## 1. 範囲

第4段階で扱うのは次の 5 つ。

| 記号 | 内容 |
|------|------|
| V | 上下位置の既定値をフォルダ本体 (蓋を除く) の見た目の中心に合わせる (−0.04 = 「下4%」) |
| E | お気に入りの一部だけを `.folderartpack` に書き出す (帯の「…」メニュー → チェックリストの popover) |
| U | ユーザー辞書 `suggestions-user.json` (同梱辞書と同じ形式、ユーザー側が優先、ファイル監視で自動再読み込み、「ファイル > 提案辞書を開く…」) |
| C | `build-xcstrings.py` にコンパイラ抽出のキー (`.stringsdata`) との厳密照合を追加 |
| M | 第3段階の残件: 走査テストのゲート解放を `defer` で囲む |

加えて README (使い方・ユーザー辞書の形式・構成) を 1.5.0 に合わせる (§8)。メイン画像は撮り直さない (画面の構成は変わらないため)。

第5段階以降に送るもの: 提案辞書への他 6 言語のキー (ユーザー辞書で各自補える)、Finder 拡張・クイックアクション、512px 以外のアイコン表現。

## 2. 決定事項 (対話で確定)

- フォルダの形は OS 規定 (`NSWorkspace.shared.icon(for: .folder)` を実行時に描く) なので、「中央」の意味は変えず **既定値だけを −0.04 にする**。保存済みのお気に入り・履歴の見た目は変えない。
- 一部書き出しの選択は **「…」メニューからチェックリストの popover**。チップのクリック (= 復元) の意味は変えない。
- ユーザー辞書は **ファイルの変更を監視して自動で読み直す**。メニューは「提案辞書を開く…」の 1 つだけ。
- 文言チェックは型を推測せず、**コンパイラが抽出した実物のキーと突き合わせる**。
- 新しいウィンドウやシートは増やさない (popover は可)。

## 3. 上下位置の既定値 (V)

### 3.1 値と根拠

- `CompositionSettings.verticalOffset` の既定値を `0.0` → `-0.04` (負 = 下、スライダー表示「下4%」)。
- 根拠 (2026-09-06、macOS 15.7 で実測): 標準フォルダアイコンを 512px に描き、不透明 (alpha > 0.5) な画素の幅が行の最大幅の 90% 以上ある行を「本体」(蓋を除く) とすると、本体は y = 99…454、その中心 276.5 は正方形の中央 256 より 20.5px = **4.0%** 下。形の中心 (蓋を含む不透明行 62…456 の中心 259) からは 3.4% 下。
- コメントに実測手順を書き、値は定数にする (起動時に測って既定にする案は、`CompositionSettings()` の意味が環境で変わるので採らない)。

### 3.2 効く範囲

- 新しく作る設定 (`CompositionSettings()`): 起動直後の入力、提案チップとお気に入りチップのサムネイル、`decodeIfPresent` で欄が無かった保存データ (v2 の行は全て欄を持つので実質なし)。
- 保存済みのお気に入り・履歴・パックは値 (多くは 0.0) を持つので変わらない。1.4.0 以前の見た目との互換はこれで保つ。
- 「中央オーバーレイ」「右下バッジ」の両方に効く (`calculateRect` の `yShift` は共通)。バッジは元々下寄りなので −4% はごく小さな差。

### 3.3 テスト

- `IconComposerTests.testDefaultVerticalOffsetMatchesFolderBodyCenter`: `IconComposer.standardFolderIcon` を 512px に描き、§3.1 の手順で本体の中心を求め、`(中心 − 256) / 512` と `-CompositionSettings().verticalOffset` の差が **0.015 以下** であること。Apple がアイコンの形を変えた macOS で落ちて知らせる (そのときは既定値を測り直す)。
- 既定値を見ている既存テスト (`CompositionSettingsTests` の既定値、`IconTaskTests` の「新規欄は初期値」) を −0.04 に更新。

## 4. お気に入りの一部書き出し (E)

### 4.1 画面

- `PresetStripView` の「…」メニューに「選んで書き出す…」を追加 (「パックを書き出す…」の直後。お気に入りが 0 件なら無効)。
- 選ぶと `@State showsExportPicker = true` になり、「…」の `Menu` に付けた `.popover(isPresented:)` で `PresetExportPickerView` を出す (幅 280pt 程度、高さは件数に応じて最大 320pt でスクロール)。
- popover の中身: 見出し「お気に入りを選んで書き出す」、お気に入りごとに 1 行 (チェックボックス + 40pt のサムネイル + 名前、帯と同じ順)、下に「すべて選択」「選択解除」と「書き出す (N 件)」(N = 0 なら無効)。「書き出す」で popover を閉じて `NSSavePanel` へ。Esc やクリック外で閉じれば何もしない。
- サムネイルは `PresetStripView` の `PresetChip` を `internal` にして流用する。

### 4.2 部品

```swift
struct PresetExportSelection: Equatable {
    private(set) var selectedIDs: Set<UUID> = []
    mutating func toggle(_ id: UUID)
    mutating func selectAll(_ presets: [Preset])
    mutating func clear()
    func selected(from presets: [Preset]) -> [Preset]   // 帯の順を保つ
    var count: Int { selectedIDs.count }
}
```

- `AppModel.exportPack()` (全件、ファイルメニューと「パックを書き出す…」) は今のまま。新しく `exportPack(presets: [Preset])` を足し、`NSSavePanel` の既定名は全件と同じ `FolderArt-お気に入り-<yyyyMMdd>.folderartpack`、書き込みは `exportPack(to:presets:)` に一般化 (`PackWriter.write(_:assets:appVersion:)` は既に配列を受ける)。空配列は `exportPack()` と同じ理由のアラート (「書き出せるお気に入りがありません。」) を出して戻る。
- パックの形式・`format`・読み込み側は変更なし。

### 4.3 文言 (8 言語で `strings.json` に追加)

「選んで書き出す…」「お気に入りを選んで書き出す」「すべて選択」「書き出す (%lld 件)」(en/de/es/fr/pt-BR は単複の variation)。「選択解除」は既存キーを使う。

### 4.4 テスト

- `PresetExportSelectionTests`: toggle の反転、selectAll / clear、`selected(from:)` が帯の順、存在しない ID は無視。
- `AppModelTests`: 2 件のうち 1 件を `exportPack(to:presets:)` で書き出すとパックの項目がその 1 件だけ (名前で確認)、空配列はファイルを作らずアラート。

## 5. ユーザー辞書 (U)

### 5.1 ファイル

- 場所: `HistoryStore.appSupportDirectory/suggestions-user.json` (履歴・お気に入りと同じディレクトリ)。
- 形式: 同梱の `suggestions.json` と同じ JSON 配列 `[{"keys": [...], "symbol": "...", "emoji": "..."}]`。`symbol` と `emoji` はどちらか片方でよい (同梱辞書の規則と同じ)。
- 読み込み時の正規化: `keys` の各要素に `SuggestionEngine.normalize` (NFKC + 小文字化) をかけ、空になったキーは捨てる。`keys` が空になった項目は捨てる。日本語キーの「2 文字以上」の規則は **ユーザー辞書には課さない** (自分の運用で 1 文字を使いたい人を止めない)。

### 5.2 合成

```swift
extension SuggestionDictionary {
    /// ユーザー辞書の項目を先頭に置き、同じキーを持つ同梱項目からはそのキーを外す。キーが無くなった同梱項目は捨てる
    static func merging(user: SuggestionDictionary, bundled: SuggestionDictionary) -> SuggestionDictionary
    /// 無ければ nil、読めない・形式が違えば .failure
    static func loadUser(at url: URL) -> Result<SuggestionDictionary, Error>?
}
```

- 合成後も「1 つのキーは 1 項目にしか現れない」(既存テストの規則) が保たれる。存在しない記号名は今どおり提案時に `catalog.contains` で飛ばす (辞書の読み込みでは弾かない。ユーザーが未来の macOS の記号名を書いても壊れない)。
- 提案の優先順 (お気に入り → 辞書 → 検索語 → 規則) と辞書内の並び (長いキー優先) は変えない。ユーザー項目が先頭にあるのは同じ長さで当たったときのタイブレークにだけ効く。

### 5.3 再読み込みと監視

- `AppModel.suggestionEngine` を `private(set) var` にし、`reloadUserDictionary()` を公開する: `loadUser` → `merging` → `SuggestionEngine(dictionary:catalog:)` を作り直し → `refreshSuggestions` (中身の走査結果は使い回す。再走査しない)。
- 監視: 新規 `Services/DirectoryWatcher.swift`。`DispatchSource.makeFileSystemObjectSource(fileDescriptor:eventMask: .write, queue:)` で **ディレクトリ** を監視する (エディタの保存は削除 + 改名で行われることが多く、ファイル自体を監視すると追えない)。イベントは 0.3 秒でまとめ、メインで通知する。`AppModel` は通知のたびにユーザー辞書の (更新日時, サイズ) を前回読み込み時と比べ、変わっていれば `reloadUserDictionary()`。ディレクトリが無い間は監視を始めず、「提案辞書を開く…」でディレクトリを作ったときに始める。
- 壊れた JSON: 同梱辞書だけの `SuggestionEngine` に戻し、`errorMessage = "提案辞書を読めません: <理由>"`。同じ内容 (更新日時, サイズ) では二度出さない。
- 起動時: `AppModel.init` で 1 回 `reloadUserDictionary()` 相当を行う (読めなければ起動時のアラートに合流)。

### 5.4 入口

- 「ファイル > 提案辞書を開く…」(`FolderArtApp` の `.commands`、既存のパックの 2 項目の後)。`AppModel.revealUserDictionary()`: ファイルが無ければディレクトリごと作り、例を 1 件入れたテンプレートを書く:
  ```json
  [
    {"keys": ["example", "サンプル"], "symbol": "star.fill", "emoji": "⭐"}
  ]
  ```
  その後 `NSWorkspace.shared.activateFileViewerSelecting([url])` で Finder に選択表示する。適用中でも可 (読むだけ)。
- README にファイルの場所・形式・例・「保存すると自動で反映」を書く。

### 5.5 テスト

- `SuggestionDictionaryTests`: `merging` (同じキーはユーザーが勝つ、キーが無くなった同梱項目は消える、無関係な項目は残る、合成後もキーの重複なし)、`loadUser` (無い → nil、壊れた JSON → failure、キーの正規化、空キー・空項目の破棄)。
- `AppModelTests`: `reloadUserDictionary()` 後に提案が変わる、壊れた JSON でアラートが 1 回だけ、`revealUserDictionary()` がテンプレートを作る (Finder 表示はテストしない)。
- `DirectoryWatcherTests`: ディレクトリにファイルを書くと 1 秒以内に通知が来る、連続した書き込みが 1 回にまとまる、解放後は通知が来ない。
- `AppModelTests`: 監視経由で自動に読み直す (ユーザー辞書を書き換え → 期限付きポーリングで提案が変わるのを待つ)。

## 6. 文言チェックの実物照合 (C)

- `scripts/localization/build-xcstrings.py --stringsdata <DerivedData>`: `**/*.stringsdata` (JSON: `tables.Localizable[].key`) からキーを集め、`strings.json` のキー集合と **厳密に** 比較する (正規化しない)。コードにあってカタログに無いキーがあれば一覧を出して exit 1、カタログにあってコードに無いキーは情報として出す (`InfoPlist` のキーとメニューの自称は対象外)。
- `scripts/localization/check-compiled.sh`: 一時 DerivedData に `xcodebuild build … SWIFT_EMIT_LOC_STRINGS=YES` してから上を実行し、終わったら一時ディレクトリを消す。PR 前の手順 (計画の Global Constraints) に加える。
- 既存の正規表現モード (`--check`) は速い簡易版として残す。2026-09-06 の確認: 1.4.0 のソースからコンパイラが抽出したキーは 148 件で、カタログの 148 キーと一致した。

## 7. 残件 (M)

- `AppModelTests` の走査テストで `gate.signal()` を `defer` に移す (途中で throw しても背景スレッドを解放する)。挙動は変えない。

## 8. README

- 使い方 3 に「上下位置の既定は下4% (蓋つきのフォルダ本体の中心)」を追記。
- 使い方 6 (お気に入り) に「…」の「選んで書き出す…」を追記。
- 「提案辞書のカスタマイズ」の節を新設: 場所、形式、例、優先規則、自動反映、記号名の探し方 (記号タブの検索)。
- 構成に `Views/PresetExportPickerView.swift`、`Services/DirectoryWatcher.swift`、`scripts/localization/check-compiled.sh` を追加。

## 9. エラー処理

| 事象 | 扱い |
|------|------|
| ユーザー辞書が壊れている | 同梱辞書だけで動く。内容が変わるたびに 1 回アラート |
| ユーザー辞書の記号名が無い | 提案時に飛ばす (アラートなし) |
| Application Support が無い | 監視しない。「提案辞書を開く…」で作る |
| 一部書き出しで 0 件 | 書き出しボタンを無効にする。万一空で呼ばれたら全件と同じアラート |
| 書き出しの保存失敗 | 既存の「パックを書き出せませんでした」アラート |
| `.stringsdata` が見つからない | `--stringsdata` は理由を出して exit 2 (ビルド設定の指定漏れ) |

## 10. テスト方針の要約

新規テストは §3.3、§4.4、§5.5。既存 247 件は維持 (既定値の更新に伴う修正を除く)。UI は実機で確認: 起動直後のスライダーが「下4%」でプレビューが本体の中心に見える、「選んで書き出す…」の popover で 2 件中 1 件を書き出して読み戻す、ユーザー辞書をエディタで保存すると提案が変わる、「提案辞書を開く…」で Finder が開く。

## 11. 影響を受ける既存ファイル

| ファイル | 変更 |
|----------|------|
| `Models/CompositionSettings.swift` | 既定値 −0.04 と実測のコメント |
| `Views/PresetStripView.swift` | 「選んで書き出す…」、popover、`PresetChip` を internal に |
| `Views/PresetExportPickerView.swift` | 新規 |
| `Models/PresetExportSelection.swift` | 新規 |
| `AppModel.swift` | `exportPack(presets:)` / `exportPack(to:presets:)`、`suggestionEngine` の差し替え、`reloadUserDictionary()`、`revealUserDictionary()`、監視 |
| `Services/SuggestionDictionary.swift` | `merging(user:bundled:)`、`loadUser(at:)` |
| `Services/DirectoryWatcher.swift` | 新規 |
| `FolderArtApp.swift` | 「提案辞書を開く…」 |
| `ContentView.swift` | 帯への `onExportSelected` の配線 |
| `scripts/localization/build-xcstrings.py`, `check-compiled.sh` | `--stringsdata` モード、補助スクリプト |
| `scripts/localization/strings.json`, `Resources/Localizable.xcstrings` | 文言の追加 (再生成) |
| `FolderArtTests/AppModelTests.swift` | `defer`、書き出し・辞書のテスト |
| `project.yml` | 1.5.0 / ビルド 8 |
| `README.md` | §8 |
