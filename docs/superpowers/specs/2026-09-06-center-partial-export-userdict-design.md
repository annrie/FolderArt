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

加えて README (使い方・ユーザー辞書の形式・構成) を 1.5.0 に合わせる (§8)。メイン画像は撮り直さない (常時見える画面の構成は変わらないため。メニューと popover は README で文章だけで説明する)。

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
- 保存済みのお気に入り・履歴・パックは値 (多くは 0.0) を持つので変わらない。アプリが書いた JSON は常に全欄を持つ (`Codable` の合成エンコード)。**欄が無い JSON** (手書きのパック、v1 の履歴行) は `decodeIfPresent` の既定として新しい −0.04 になる: 手書きパックは「既定 = 今の既定」で自然、v1 の行は `legacyImage` で再適用できずリセットにしか使わないので見た目に関係しない。旧既定 0.0 を保つ互換デコードは入れない (この挙動を README の注意に 1 行書く)。
- 「中央オーバーレイ」「右下バッジ」の両方に効く (`calculateRect` の `yShift` は共通)。バッジは元々下寄りなので −4% はごく小さな差。

### 3.3 テスト

- 実測の関数 `IconComposer.folderBodyCenterOffset(of image: NSImage, side: Int = 512) -> Double?` (§3.1 の手順を純関数にしたもの。不透明行が無ければ nil) を公開し、次の 2 本でテストする:
  1. **固定の図形** (蓋 = 幅 40% × 高さ 10%、本体 = 幅 100% × 高さ 70% の合成画像) で本体中心のずれが計算どおり (例: −0.05) になること。ロジックのテストで OS に依存しない。
  2. **起動中の OS のアイコン** (`IconComposer.standardFolderIcon`) で求めた値と `-CompositionSettings().verticalOffset` の差が **0.015 以下** であること。これは環境依存の「見張り」テストで、Apple がアイコンの形を変えた macOS で落ちて知らせる (メッセージに実測値を出し、既定値を測り直す手がかりにする)。対象は macOS 13+ だが開発機は 15.7 なので、落ちたら既定値の見直し (OS ごとの値を持つか) を検討する。
- 既定値を見ている既存テスト (`CompositionSettingsTests` の既定値、`IconTaskTests` の「新規欄は初期値」) を −0.04 に更新。

## 4. お気に入りの一部書き出し (E)

### 4.1 画面

- `PresetStripView` の「…」メニューに「選んで書き出す…」を追加 (「パックを書き出す…」の直後。お気に入りが 0 件なら無効)。
- 選ぶと、メニューが閉じてから popover を出すために `DispatchQueue.main.async { showsExportPicker = true }` で状態を立て、「…」の `Menu` に付けた `.popover(isPresented:)` で `PresetExportPickerView` を出す (幅 280pt 程度、高さは件数に応じて最大 320pt でスクロール)。メニューの dismiss と popover の presentation が同じ操作内で競合しないようにする。実機で不安定なら、popover の anchor を ★ ボタンと「…」を包む `HStack` に付け替える (計画の実機確認項目)。
- popover の中身: 見出し「お気に入りを選んで書き出す」、お気に入りごとに 1 行 (チェックボックス + 40pt のサムネイル + 名前、帯と同じ順)、下に「すべて選択」「選択解除」と「書き出す (N 件)」(N = 0 なら無効)。「書き出す」で popover を閉じて `NSSavePanel` へ。Esc やクリック外で閉じれば何もしない。
- サムネイルは `PresetStripView` の `PresetChip` を `internal` にして流用する。

### 4.2 部品

```swift
struct PresetExportSelection: Equatable {
    private(set) var selectedIDs: Set<UUID> = []       // 初期状態は未選択
    mutating func toggle(_ id: UUID)
    mutating func selectAll(_ presets: [Preset])
    mutating func clear()
    /// 帯の順を保つ。今のお気に入りに無い ID は無視する
    func selected(from presets: [Preset]) -> [Preset]
    /// お気に入りが増減したら呼ぶ。今のお気に入りに無い ID を捨てる
    mutating func prune(to presets: [Preset])
}
```

- 「書き出す (N 件)」の N は常に `selected(from: store.presets).count` で数える (`selectedIDs.count` は使わない)。popover を出している間にお気に入りが削除・読み込み・並び替えされたら `onChange(of: store.presets)` で `prune(to:)` を呼ぶ。

- `AppModel.exportPack()` (全件、ファイルメニューと「パックを書き出す…」) は今のまま。新しく `exportPack(presets: [Preset])` を足し、`NSSavePanel` の既定名は全件と同じ `FolderArt-お気に入り-<yyyyMMdd>.folderartpack`、書き込みは `exportPack(to:presets:)` に一般化 (`PackWriter.write(_:assets:appVersion:)` は既に配列を受ける)。空配列は `exportPack()` と同じ理由のアラート (「書き出せるお気に入りがありません。」) を出して戻る。
- パックの形式・`format`・読み込み側は変更なし。

### 4.3 文言 (8 言語で `strings.json` に追加)

「選んで書き出す…」「お気に入りを選んで書き出す」「すべて選択」「書き出す (%lld 件)」(en/de/es/fr/pt-BR は単複の variation)。「選択解除」は既存キーを使う。

### 4.4 テスト

- `PresetExportSelectionTests`: toggle の反転、selectAll / clear、`selected(from:)` が帯の順で存在しない ID は無視、`prune(to:)` で消えた ID が落ちる。
- `AppModelTests`: 2 件のうち 1 件を `exportPack(to:presets:)` で書き出すとパックの項目がその 1 件だけ (名前で確認)、空配列はファイルを作らずアラート (`NSSavePanel` を出す前に戻る経路も同じ判定を通る)。
- 実機: popover を Esc とクリック外で閉じても何も起きない、保存パネルのキャンセル、popover 表示中にお気に入りを削除すると件数が減る。

## 5. ユーザー辞書 (U)

### 5.1 ファイル

- 場所: `HistoryStore.appSupportDirectory/suggestions-user.json` (履歴・お気に入りと同じディレクトリ)。
- 形式: 同梱の `suggestions.json` と同じ JSON 配列 `[{"keys": [...], "symbol": "...", "emoji": "..."}]`。`symbol` と `emoji` はどちらか片方でよい (同梱辞書の規則と同じ)。
- 読み込み時の正規化と整理 (`loadUser` の中で行う。順に):
  1. `keys` の各要素を NFKC + 小文字化し (`SuggestionEngine.normalize` は camelCase の境界に空白を入れるので使わない。辞書のキーは同梱辞書と同じ「小文字の 1 語」)、前後の空白を落とす。空になったキーは捨てる。項目内の重複キーは 1 つにまとめる。
  2. 項目間で同じキーが出たら **先の項目が勝ち**、後の項目からそのキーを外す。
  3. `symbol` と `emoji` は空文字を nil と同じに扱い、両方 nil の項目は捨てる。
  4. `keys` が空になった項目は捨てる。
  日本語キーの「2 文字以上」の規則は **ユーザー辞書には課さない** (自分の運用で 1 文字を使いたい人を止めない)。
- 上限 (超えたら読み込み失敗として扱い、同梱辞書だけで動く): ファイル 1 MB、項目 1,000、項目あたりの `keys` 50、キー 64 書記素、`symbol` 100 書記素、`emoji` 8 書記素 (パックの `PackReader.withinLimit` と同じ「書記素数 + UTF-8 バイト数」の判定を使う)。

### 5.2 合成

```swift
extension SuggestionDictionary {
    /// ユーザー辞書の項目を先頭に置き、同じキーを持つ同梱項目からはそのキーを外す。キーが無くなった同梱項目は捨てる
    static func merging(user: SuggestionDictionary, bundled: SuggestionDictionary) -> SuggestionDictionary
    /// 無ければ nil、読めない・形式が違う・上限超えなら .failure (§5.1 の正規化と整理は成功側で済ませてある)
    static func loadUser(at url: URL) -> Result<SuggestionDictionary, Error>?
}
```

- `merging` はユーザー辞書が §5.1 で重複を解消済みであることを前提にする (テストで担保)。合成後も「1 つのキーは 1 項目にしか現れない」(既存テストの規則) が保たれる。存在しない記号名は今どおり提案時に `catalog.contains` で飛ばす (辞書の読み込みでは弾かない。ユーザーが未来の macOS の記号名を書いても壊れない)。
- 提案の優先順 (お気に入り → 辞書 → 検索語 → 規則) と辞書内の並び (長いキー優先) は変えない。ユーザー項目が先頭にあるのは同じ長さで当たったときのタイブレークにだけ効く。

### 5.3 再読み込みと監視

- `AppModel.suggestionEngine` を `private(set) var` にし、`reloadUserDictionary() async` を公開する: ファイルの読み込みと JSON の復号 (`loadUser`) は `Task.detached` でメインの外、`merging` → `SuggestionEngine(dictionary:catalog:)` の作り直し → `refreshSuggestions` はメインで行う (中身の走査結果は使い回す。再走査しない)。読み込みにも世代番号を付け、古い結果は捨てる (走査と同じ規則)。
- 監視: 新規 `Services/FileWatcher.swift` (`DirectoryWatcher` ではなく、ディレクトリとファイルの両方を見る 1 つの部品)。
  - **ディレクトリ** を `O_EVTONLY` で開き `DispatchSource.makeFileSystemObjectSource(eventMask: [.write])` で監視する (作成・改名・削除で発火。原子的保存 = 一時ファイルに書いて改名、を捕まえる)。
  - **ファイル** が存在する間はファイル自体も `O_EVTONLY` で開き `[.write, .extend, .attrib, .delete, .rename]` で監視する (その場で切り詰めて書き直すエディタを捕まえる)。`.delete` / `.rename` の後はファイルを開き直す (無ければディレクトリ監視だけに戻る)。
  - cancel handler で fd を close する。イベントは 0.3 秒でまとめ、メインで通知する。
  - ディレクトリが無い間は監視を始めず、「提案辞書を開く…」でディレクトリを作ったときに始める。
- 通知のたびに **必ず** `reloadUserDictionary()` を呼ぶ (ファイルは 1 MB 以下なので、更新日時とサイズで変更を推定して読み飛ばすことはしない)。
- 壊れた JSON・上限超え: 同梱辞書だけの `SuggestionEngine` に戻し、`errorMessage = "提案辞書を読めません: <理由>"`。同じ内容では二度出さないよう、失敗したファイルの内容のハッシュ (SHA-256) を覚え、同じハッシュなら黙る。直して保存されれば復帰し、次に壊れたときはまた 1 回出す。
- 起動時: `AppModel.init` で 1 回 `reloadUserDictionary()` を起動する。読めなかったときの文言は、保存データの読み込みエラー (`history.loadError ?? presets.loadError`) があればその後ろに空行を挟んで連結し、1 つのアラートで出す (上書きしない)。

### 5.4 入口

- 「ファイル > 提案辞書を開く…」(`FolderArtApp` の `.commands`、既存のパックの 2 項目の後)。`FolderArtApp` は `AppModel` を持たないので、パックのメニューと同じく `AppModel.revealUserDictionaryNotification` を post し、`ContentView` の `onReceive` で `model.revealUserDictionary()` を呼ぶ。`revealUserDictionary()`: ファイルが無ければディレクトリごと作り、例を 1 件入れたテンプレートを書く:
  ```json
  [
    {"keys": ["example", "サンプル"], "symbol": "star.fill", "emoji": "⭐"}
  ]
  ```
  その後 `NSWorkspace.shared.activateFileViewerSelecting([url])` で Finder に選択表示する。適用中でも可 (読むだけ)。
- README にファイルの場所・形式・例・「保存すると自動で反映」を書く。

### 5.5 テスト

- `SuggestionDictionaryTests`: `merging` (同じキーはユーザーが勝つ、キーが無くなった同梱項目は消える、無関係な項目は残る、合成後もキーの重複なし)、`loadUser` (無い → nil、壊れた JSON → failure、上限超え → failure、キーの正規化、項目内・項目間の重複解消 (先勝ち)、空キー・空項目・symbol と emoji が両方無い項目の破棄、空文字は nil 扱い)。
- `AppModelTests` (`appSupportDirectory` に依存しないよう、ユーザー辞書の URL を init で注入できるようにする): `reloadUserDictionary()` 後に提案が変わる、壊れた JSON でアラートが 1 回だけで同じ内容では再度出ない、直した JSON で復帰する、`revealUserDictionary()` がテンプレートを作る (Finder 表示はテストしない)、起動時に保存データのエラーと辞書のエラーが連結される。
- `FileWatcherTests`: ディレクトリに新しいファイルを書くと 1 秒以内に通知が来る、原子的保存 (一時ファイルに書いて改名) でも通知が来る、その場での書き直し (truncate + write) でも通知が来る、連続した書き込みが 1 回にまとまる、解放後は通知が来ない。
- `AppModelTests`: 監視経由で自動に読み直す (ユーザー辞書を書き換え → 期限付きポーリングで提案が変わるのを待つ)。

## 6. 文言チェックの実物照合 (C)

- `scripts/localization/build-xcstrings.py --stringsdata <DerivedData>`: `**/*.stringsdata` からキーを集め、`strings.json` のキー集合と **厳密に** 比較する (正規化しない)。コードにあってカタログに無いキーがあれば一覧を出して exit 1、カタログにあってコードに無いキーは情報として出す (`InfoPlist` のキーとメニューの自称は対象外)。
- `.stringsdata` の形式 (2026-09-06、Xcode 26.2 で `SWIFT_EMIT_LOC_STRINGS=YES` を付けてビルドした実物。ソースファイルごとに 1 つ):
  ```json
  {"source": "/…/FolderArt/AppModel.swift",
   "tables": {"Localizable": [
     {"comment": "", "key": "保存データの読み込みに失敗しました: %@", "location": {"startingColumn": 46, "startingLine": 71}},
     {"comment": "", "key": "%lld フォルダに適用", "location": {"startingColumn": 33, "startingLine": 126}}]},
   "version": 1}
  ```
  `tables` は「テーブル名 → 項目の配列」の辞書。文言が無いファイル (例: `Info.plist` 由来の AppShortcuts の metadata) は `"tables": {}`。パーサは `tables` が辞書でなければそのファイルを飛ばし、`Localizable` 以外のテーブルは無視し、項目は `{"key": …}` のオブジェクトか素の文字列のどちらでも受ける (将来の形式差に備える)。`.stringsdata` が 1 つも無ければ理由を出して exit 2。
- `scripts/localization/check-compiled.sh`: 一時 DerivedData に `xcodebuild build … SWIFT_EMIT_LOC_STRINGS=YES` してから上を実行し、終わったら一時ディレクトリを消す。PR 前の手順 (計画の Global Constraints) に加える。
- 既存の正規表現モード (`--check`) は速い簡易版として残す。2026-09-06 の確認: 1.4.0 のソースからコンパイラが抽出したキーは 148 件で、カタログの 148 キーと一致した。

## 7. 残件 (M)

- `AppModelTests` の走査テストで `gate.signal()` を `defer` に移す (途中で throw しても背景スレッドを解放する)。挙動は変えない。

## 8. README

- 使い方 3 に「上下位置の既定は下4% (蓋つきのフォルダ本体の中心)」を追記。
- 使い方 6 (お気に入り) に「…」の「選んで書き出す…」を追記。
- 「提案辞書のカスタマイズ」の節を新設: 場所、形式、例、優先規則、自動反映、記号名の探し方 (記号タブの検索)。
- 構成に `Views/PresetExportPickerView.swift`、`Models/PresetExportSelection.swift`、`Services/FileWatcher.swift`、`scripts/localization/check-compiled.sh` を追加。
- 注意の節に「欄の無い手書きパックの上下位置は既定 (下4%) になる」を 1 行。

## 9. エラー処理

| 事象 | 扱い |
|------|------|
| ユーザー辞書が壊れている・上限超え | 同梱辞書だけで動く。同じ内容 (ハッシュ) では 1 回だけアラート。直せば復帰 |
| 起動時に保存データと辞書の両方が読めない | 1 つのアラートに空行で連結して出す |
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
| `Services/FileWatcher.swift` | 新規 (ディレクトリとファイルの両方を監視) |
| `FolderArtApp.swift` | 「提案辞書を開く…」(通知を post) |
| `ContentView.swift` | 帯への `onExportSelected` の配線、`revealUserDictionaryNotification` の受け口 |
| `scripts/localization/build-xcstrings.py`, `check-compiled.sh` | `--stringsdata` モード、補助スクリプト |
| `scripts/localization/strings.json`, `Resources/Localizable.xcstrings` | 文言の追加 (再生成) |
| `FolderArtTests/AppModelTests.swift` | `defer`、書き出し・辞書のテスト |
| `project.yml` | 1.5.0 / ビルド 8 |
| `README.md` | §8 |
