# FolderArt 第3段階: フォント・太さの UI、多言語化、フォルダの中身からの生成

作成日: 2026-09-05
対象バージョン: 1.4.0 (現行 1.3.0、ビルド 6 → 7)
状態: 設計確定 (実装計画は別ファイル)
前提: 第1段階 spec `2026-09-02-overlay-sources-and-batch-design.md` (v1.2.0)、第2段階 spec `2026-09-03-suggestions-packs-and-maintenance-design.md` (v1.3.0) が実装済み

## 1. 範囲

第3段階で扱うのは次の 3 つ。

| 記号 | 内容 |
|------|------|
| F | 文字のフォントと、記号・文字の太さを選ぶ UI (第1段階でモデルに `fontName` / `fontWeight` を用意済み) |
| L | 多言語化: TuneR / YTDown と同じ 8 言語 (ja / en / de / es / fr / ko / pt-BR / zh-Hant) + アプリ内の言語メニュー |
| B | フォルダの中身からの生成: 直下のファイルの種類から記号・絵文字を、画像が多ければ代表画像を提案に足す (第2段階からの持ち越し) |

加えて README の機能一覧・プロジェクト構成・メイン画像を 1.4.0 に合わせる (§8)。

第4段階以降に送るもの: 提案辞書のユーザー編集と他 6 言語のキー、お気に入りの一部だけの書き出し、Finder 拡張・クイックアクション、512px 以外のアイコン表現。

## 2. 決定事項 (対話で確定)

- 中身は **種類 + 代表画像の両方** を見る。走査は **直下のみ**、代表画像は **更新日時が最新** のもの。名前からの候補を優先し、空いた枠だけ中身で埋める。
- フォントは **macOS 同梱の厳選リスト** (8 種) から選ぶ。太さは **regular〜black の 6 段階**、記号と文字の両方に効く。
- 言語は **8 言語**、既定は日本語、未対応の言語は **英語にフォールバック** (両アプリの `fallbackLocale: 'en'` と同じ)。切り替えは **アプリ内の言語メニュー** で、選ぶと保存して **再起動を促す** (macOS は起動中の言語切り替えを持たないため)。
- 新しいウィンドウやシートは増やさない (第1・第2段階と同じ方針)。

## 3. フォント・太さの UI (F)

### 3.1 FontCatalog

```swift
struct FontChoice: Identifiable, Equatable {
    let family: String?          // nil = システム丸ゴシック (CompositionSettings.fontName の nil と同じ意味)
    let title: LocalizedStringKey
    var id: String { family ?? "" }
}

enum FontCatalog {
    static let choices: [FontChoice]                 // 下の 8 種、この順
    /// この Mac にある家族名。起動後 1 回だけ取得してキャッシュ (描画のたびに NSFontManager を引かない。起動後に入れたフォントは次回起動から)
    static let installedFamilies: Set<String>        // = Set(NSFontManager.shared.availableFontFamilies)
    /// この Mac にあるものだけ。先頭 (nil) は常に含む
    static func available(families: Set<String> = installedFamilies) -> [FontChoice]
    /// family + weight から NSFont を作る (OverlayRenderer.makeFont はこれを呼ぶだけになる)。family が nil なら families を見ない
    static func font(family: String?, weight: FontWeightValue, size: CGFloat,
                     families: Set<String> = installedFamilies) -> NSFont
}
```

| 表示名 (ja) | `family` | 備考 |
|------------|----------|------|
| 丸ゴシック (システム) | `nil` | 既定。現行と同じ `NSFont.systemFont(weight:)` + `.rounded` |
| ヒラギノ角ゴシック | `Hiragino Sans` | W3〜W8 の 6 段階が太さに対応 (確認済み) |
| ヒラギノ明朝 | `Hiragino Mincho ProN` | W3 / W6 の 2 段階 |
| ヒラギノ丸ゴ | `Hiragino Maru Gothic ProN` | W4 のみ (太さは効かない) |
| 筑紫A丸ゴシック | `Tsukushi A Round Gothic` | Regular / Bold |
| クレー | `Klee` | Medium / Demibold |
| Avenir Next | `Avenir Next` | 欧文。Regular〜Heavy |
| Menlo (等幅) | `Menlo` | Regular / Bold |

- `fontName` には **ファミリ名** を入れる。モデル (`CompositionSettings.fontName: String?`) の型と意味は変えない。
- `font(family:weight:size:)` の解決順:
  1. `family == nil` → 現行どおりシステムフォント + `.rounded` (太さは `weight`)。
  2. `families` に含まれる → `NSFontDescriptor(fontAttributes: [.family: family, .traits: [.weight: weight.nsWeight.rawValue]])` から `NSFont(descriptor:size:)`。無い太さは一番近い顔になる。返った `NSFont.familyName` が `family` と違えば (置き換えが起きた) 3 へ。この解決は 8 家族すべてについて確認済み: Hiragino Sans は W3/W4/W5/W6/W7/W8 が 6 段階に 1 対 1、Hiragino Mincho ProN は W3/W6、Hiragino Maru Gothic ProN は W4 のみ、Tsukushi A Round Gothic は Regular/Bold、Klee は Medium/Demibold、Avenir Next は Regular/Medium/DemiBold/Bold/Heavy、Menlo は Regular/Bold。`choices` には正規の家族名だけを持ち、表示名や PostScript 名で引かないので、名前の種類のずれは起きない。
  3. `NSFont(name: family, size:)` (1.3.0 までのパックに PostScript 名が入っていた場合の互換)。
  4. どれも無ければ 1 の既定に落ちる (別の Mac で作られたパックの家族が無くても描ける)。
- 記号の太さは現行の `NSImage.SymbolConfiguration(weight:)` のまま。絵文字と画像には太さもフォントも効かない。
- `FontWeightValue` に表示名を足す: regular「標準」/ medium「中太」/ semibold「半太」/ bold「太字」/ heavy「特太」/ black「極太」。

### 3.2 画面

- `ControlsView` の「色:」の行の下に 2 行を足す。
  - 「フォント:」`Picker` (`.menu`、ラベル幅 80 は他の行と同じ)。選択肢は `FontCatalog.available()`。**文字タブでのみ有効**、他のタブでは色と同じ 0.4 の無効表示。
  - 「太さ:」`Picker` (`.menu`、6 段階)。**記号と文字のタブで有効**、画像・絵文字では無効表示。
- `settings.fontName` が一覧に無いとき (別の Mac のパック、家族が無い Mac、旧 PostScript 名) は「その他 (名前)」を一時的な選択肢として末尾に出す (SwiftUI の `Picker` は選択値が一覧に無いと空表示になるため)。この項目は選び直せば消える。設定の値を勝手に書き換えない。
- `ControlsView` の引数は `showsTint` に加えて `showsFont: Bool` (文字タブ) と `showsWeight: Bool` (記号または文字タブ) を `ContentView` が渡す。
- 2 行 (約 60pt) 増えるので、`ContentView` の `minHeight` と `FolderArtApp` の `defaultSize` の高さを 720 → 780 にする。
- プレビューは `settings` の変更で現行どおり自動更新 (`OverlayState` の debounce)。

### 3.3 保存と互換

- お気に入り・履歴・パックは `settings` をそのまま持つので変更なし。`PackReader` の `fontName` 上限 (100 書記素) と `isValid` (空文字でない) もそのまま。
- 1.3.0 で作った保存データは `fontName == nil` なので見た目が変わらない。
- 逆方向 (1.4.0 が書いたパックを 1.3.0 で読む): 1.3.0 の `makeFont` は `NSFont(name:)` だけなので、家族名は解決できることもある (CoreText は PostScript 名 → フルネーム → 家族名の順で当てる) が、太さは既定の顔になる。解決できなければ丸ゴシック。**1.3.0 での見た目の差は許容する** (第2段階の方針どおり、パックの `format` は 1 のまま。項目の形は変わっていない)。

### 3.4 テスト

- `FontCatalogTests`: `nil` → 丸ゴシック (`fontDescriptor.object(forKey: .design)` または `fontName` に `Rounded` を含む)、既知の家族 → `familyName` 一致、`Hiragino Sans` の regular / bold / black がそれぞれ `HiraginoSans-W3` / `HiraginoSans-W6` / `HiraginoSans-W8`、`Hiragino Maru Gothic ProN` はどの太さでも `HiraMaruProN-W4` (無い太さは一番近い顔)、`families` に無い家族 → 落ちずに既定へ、PostScript 名 (`HiraginoSans-W6`) は 3 の経路で解決、`available()` は先頭が `nil` で `families` に無いものを含まない。
- `OverlayRendererTests`: `fontName = "Hiragino Mincho ProN"` の文字が描けて不透明画素がある。

## 4. 多言語化 (L)

### 4.1 言語とカタログ

- 言語コード: `ja`, `en`, `de`, `es`, `fr`, `ko`, `pt-BR`, `zh-Hant`。
- `Resources/Localizable.xcstrings` を 1 つ。**キーは現行の日本語リテラルのまま** (コード側の `Text("…")` / `String(localized:)` は触らない)。`sourceLanguage` は `en` とし、`en` の値も明示的に持つ (キーが日本語なので、明示しないと英語環境で日本語が出る)。全項目 `extractionState: manual` にして Xcode の同期に既存の値を触らせない (新しいキーは実装時に手で足す)。8 言語すべてを `translated` にする。
- この組み合わせ (開発言語 en + 日本語キー + en の値を明示) は `xcrun xcstringstool compile` で確認済み: `en.lproj/Localizable.strings` に英語の値、`ja.lproj` にキーと同じ値、単複の variation は `en.lproj/Localizable.stringsdict` に出る。訳の無いキーはその言語の `.lproj` に出ないので、実行時に開発言語 (en) へ落ちる。
  - 退けた案: 開発言語を ja にする (未対応の言語で日本語が出て、TuneR / YTDown の en フォールバックと合わない)。キーを英語に書き換える (全ファイルの文言を触る大きな差分になり、§2 の「コードの文言は触らない」に反する)。
- `project.yml` に `options.developmentLanguage: en` を明記し、`LOCALIZATION_PREFERS_STRING_CATALOGS: YES` と `SWIFT_EMIT_LOC_STRINGS: YES` を `FolderArt` の settings に足す (Xcode がビルド時にカタログへ新しいキーを同期できるようにする)。XcodeGen 2.46 は `.xcstrings` をリソースとして扱う。
- カタログのキーは Swift の補間から抽出される形に合わせる: `Int` は `%lld`、`String` は `%@` (例: `String(localized: "\(n) フォルダに適用")` → キー `%lld フォルダに適用`)。
- 単数・複数の variation は **数が 1 つだけ** の文言に入れる: 「%lld フォルダに適用」「選択した %lld フォルダに適用」「%lld 件のお気に入りを追加しました。」を en / de / es / fr / pt-BR で。ja / ko / zh-Hant は単複の区別が無いので 1 形。数を 2 つ含む「%lld 件のお気に入りを追加しました (%lld 件は同じものがあるため省略)。」と `%@` を含む「中身の多くが%@ (%lld 件)」は variation を使わず、単複で形が変わらない言い回しにする (例: en `Added %lld preset(s) (%lld skipped as identical).`)。
- `Resources/InfoPlist.xcstrings`: `FolderArt Preset Pack` (CFBundleTypeName / UTTypeDescription) を 8 言語で。
- `suggestions.json` の語と SF Symbols の検索語は日英のまま (他 6 言語のキーは第4段階)。

### 4.2 今回直す未ローカライズ箇所

| 場所 | 問題 | 直し方 |
|------|------|--------|
| `Services/BookmarkManager.swift` `errorDescription` | 素の日本語リテラル | `String(localized:)` |
| `Services/ApplyCoordinator.swift` 巻き戻し失敗の理由 (`" / 巻き戻し失敗: …"`) | 同上 | `String(localized:)` |
| `Views/DropZoneView.swift` `buttonLabel: String` | `String` を `Button` に渡すと訳が効かない | `LocalizedStringKey` に |
| `Views/ControlsView.swift` `Text(showsTint ? "…" : "…")` | 三項演算子で `String` になり訳が効かない | `showsTint ? Text("…") : Text("…")` |
| `AppModel.exportPack()` の既定ファイル名 `FolderArt-お気に入り-<日付>` | 同上 | `String(localized: "FolderArt-お気に入り-\(date)")` |

判定の基準: `Text("…")` / `Button("…")` / `Label("…")` / `Toggle("…")` / `TextField("…")` / `Menu("…")` / `.alert("…")` の文字列リテラルは `LocalizedStringKey` として訳される (日本語リテラルであること自体は問題ではない)。訳されないのは **`String` 型を経由する** 経路だけ: 三項演算子、`String` 型のプロパティや引数、`errorDescription`、`String(format:)`、`nameFieldStringValue` など。実装計画の最初のタスクで `grep` による棚卸し (`Text(` / `Button(` / `Label(` / `.help(` / `String(localized` / `errorDescription` / 文言を持つ `: String` のプロパティ) を行い、対象の全行と判定を PR の説明に載せる。表に無いものが見つかれば同じ流儀で直す。

### 4.3 言語メニュー

```swift
enum AppLanguage: String, CaseIterable, Identifiable {
    case system, ja, en, de, es, fr, ko, ptBR = "pt-BR", zhHant = "zh-Hant"
    var displayName: String   // system だけ訳す (「システムに従う」)。他は各言語の自称: 日本語 / English / Deutsch / Español / Français / 한국어 / Português (Brasil) / 繁體中文
}

@MainActor
final class LanguageSetting: ObservableObject {
    static let key = "FolderArtLanguage"
    @Published var selection: AppLanguage          // 変えると保存し、needsRelaunch を立てる
    @Published var needsRelaunch = false
    init(defaults: UserDefaults = .standard)      // 起動時は key だけを読む
    func relaunch(onFailure: @escaping (Error) -> Void)
}
```

- 入り口: 「表示」メニューに「言語」サブメニュー (`FolderArtApp` の `.commands` に `CommandGroup(after: .toolbar)` で `Picker("言語", selection:)` を置く。項目はチェックマーク付きの 9 択)。
- 保存: `selection != .system` なら自前キー `FolderArtLanguage` に rawValue、`AppleLanguages` に `[rawValue]` を書く。`.system` なら **両方を `removeObject`** する。起動時は **自前キーだけ** 読む (`AppleLanguages` は上書きしていなくてもシステムの値が読めてしまい、「システムに従う」と区別できないため)。
- `FolderArtApp` が `@StateObject var language = LanguageSetting()` を持ち、`.environmentObject` で `ContentView` に渡す。
- 反映: `needsRelaunch` で `ContentView` がアラート「言語の変更は次回起動時に反映されます。今すぐ再起動しますか？ (フォルダーのリストと今の入力は消えます)」を出す。ボタンは [再起動] [あとで]。**適用中 (`isApplying`) は [再起動] を出さない** (アラートの内容は `ViewBuilder` なので条件で省ける)。
- 状態遷移: `selection` が **変わったときだけ** `needsRelaunch = true` (同じ値の再選択では立てない)。アラートの `isPresented` は `needsRelaunch` に束ね、[あとで] でも [再起動] の失敗でも、閉じれば `false` に戻る。再提示はしない (設定は保存済みなので次回起動で反映される。適用中で [再起動] を出せなかったときも同じ)。
- 保存の反映: `UserDefaults` は cfprefsd を介するので、`set` した値は plist への書き出しを待たずに新しいプロセスから読める。`synchronize()` は呼ばない (非推奨で、効果も無い)。
- 再起動: `NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration:)` で `createsNewApplicationInstance = true` にして自分をもう 1 つ起動し、完了ハンドラで `NSApp.terminate(nil)`。起動に失敗したら終了せず `errorMessage` に理由を出す。
- 新しいインスタンスは通常起動と同じ (`reapAssets` など)。古いインスタンスは終了するだけなので保存データの競合は無い。

### 4.4 テスト

- `LanguageSettingTests` (`UserDefaults(suiteName:)` を注入): 言語を選ぶと両キーが書かれる、`.system` で両方消える、起動時に自前キーから復元する、`AppleLanguages` だけがある (システム由来) なら `.system`、選択が変わったときだけ `needsRelaunch` が立つ。
- `LocalizationTests`: `Localizable.xcstrings` を JSON として読み、全キーが 8 言語とも `translated` であること、`ja` の値がキーと一致すること (書き間違いの検出)。`en.lproj` を `Bundle(path:)` で開き、「履歴」など数個のキーが英語になっていること (どの言語のプロセスで走っても通る)。`InfoPlist.xcstrings` も同じ完全性チェック。`en.lproj/Localizable.stringsdict` に「%lld フォルダに適用」の `one` / `other` があること。`String(localized:bundle:locale:)` を `en.lproj` の `Bundle` と `Locale(identifier: "en")` で評価し、1 なら `folder`、2 なら `folders` になること。
- 既存テストは `String(localized:)` で比較しているので言語に依存しない。`ApplyCoordinatorTests` の `contains("履歴の保存に失敗")` だけ `String(localized:)` に直す。

## 5. フォルダの中身からの生成 (B)

### 5.1 ContentScanner

```swift
enum ContentKind: CaseIterable, Sendable {
    case image, video, audio, pdf, presentation, spreadsheet, code, document, archive, app, folder
    var dictionaryKey: String        // 辞書の代表キー: photo / video / music / pdf / presentation / spreadsheet / code / document / zip / app / (folder は無し)
    var displayName: String          // 理由の文言用 (画像 / 動画 / 音楽 / PDF / プレゼン / 表計算 / コード / 書類 / 圧縮ファイル / アプリ / フォルダ)
}

struct RepresentativeImage: Equatable, Sendable {
    let url: URL
    let modificationDate: Date                       // 同じ path の画像が更新されたことを見分ける (Suggestion の id に使う)
    let thumbnailPNG: Data                           // 長辺 256px 以下の PNG (チップ用)。等価判定には使わない
}

struct ContentSummary: Equatable, Sendable {
    let counts: [ContentKind: Int]
    let dominant: ContentKind?                       // 最多。同数は ContentKind の列挙順の先。0 件なら nil
    let representative: RepresentativeImage?         // dominant == .image のときだけ
}

enum ContentScanner {
    static let entryLimit = 1000
    static let maxImageBytes = 20 * 1024 * 1024
    static let representableTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff]   // 画像パネルと同じ
    nonisolated static func scan(_ folder: URL, limit: Int = entryLimit) -> ContentSummary?   // 読めなければ nil
    nonisolated static func thumbnailPNG(of url: URL, maxPixel: Int = 256) -> Data?
}
```

- 走査は `FileManager.enumerator(at:includingPropertiesForKeys:options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles])` で **直下のみ** を逐次読む (`contentsOfDirectory` は全件を配列にしてから返すので、巨大なフォルダやネットワークボリュームで上限が効かない)。`Icon\r` は隠し属性が付いていないことがあるので **名前でも除外**。ループの中で `limit` 件に達したら止め、毎回 `Task.isCancelled` を見て打ち切る (打ち切ったら nil)。順序は列挙の返す順 (ファイルシステム依存) なので、上限で止めた結果は「直下の一部」であり、テストもその前提で書く (件数の合計が `limit` になることだけを見る)。
- 分類は `contentTypeKey` の `UTType` を次の順で判定し、最初に当たった種類に数える。当たらないものは数えない。
  1. ディレクトリでパッケージでない → `folder`
  2. `.application` → `app`
  3. `.image` → `image`
  4. `.movie` / `.video` → `video`
  5. `.audio` → `audio`
  6. `.pdf` → `pdf`
  7. `.presentation` → `presentation`
  8. `.spreadsheet` → `spreadsheet`
  9. `.sourceCode` → `code` (`.text` より先。ソースは `.text` にも準拠するため)
  10. `.text` / `.compositeContent` → `document`
  11. `.archive` / `.diskImage` → `archive`
- `dominant == .folder` は数えるだけで **チップは出さない** (フォルダの上にフォルダ記号を重ねても意味が無い。サブフォルダが多数派なら中身からの候補は無し)。
- 代表画像: `dominant == .image` のとき、`representableTypes` のいずれかに準拠し `fileSizeKey` が `maxImageBytes` 以下の画像のうち、`contentModificationDateKey` が最新 (同時刻は `lastPathComponent` の昇順で先) の 1 枚。`thumbnailPNG` は `CGImageSourceCreateWithURL` (`kCGImageSourceShouldCache: false`) → `CGImageSourceCreateThumbnailAtIndex` に `kCGImageSourceCreateThumbnailFromImageAlways: true`、`kCGImageSourceThumbnailMaxPixelSize: 256`、`kCGImageSourceCreateThumbnailWithTransform: true` (EXIF の向きを反映) を渡して作り、PNG に書き出す (画像全体を復号せず、キャッシュも残さない)。サムネイルが作れなければ代表画像は無し。
- 記号・絵文字は **辞書 `suggestions.json` の代表キー** から引く (`SuggestionDictionary.entry(forKey:)` を足す)。辞書に単一の出典を置き、既存テスト「全 symbol がカタログにある」で担保する。辞書に無い `presentation` / `spreadsheet` の項目を足す (記号は `SymbolCatalog` にあるものをテストで確認して選ぶ。候補: `play.rectangle.fill` / `tablecells.fill`)。

### 5.2 候補の合流

```swift
enum Suggestion.Kind { case symbol(String), emoji(String), text(String), preset(Preset), image(RepresentativeImage) }
// image の等価判定と id は url + modificationDate ("image:<path>:<mtime>")。thumbnailPNG は比較しない。
// 同じ path の画像が更新されて再走査されたとき、チップの .task(id:) が新しいサムネイルを描き直せるようにする

struct SuggestionEngine {
    func suggest(for folderName: String, presets: [Preset], content: ContentSummary?) -> [Suggestion]   // 最大 4
}
```

- 名前からの候補 (第2段階の 4 層) を先に作る。`content?.dominant` が `folder` 以外なら、**記号の枠と絵文字の枠のうち空いている方だけ** 辞書の代表キーの記号・絵文字で埋める (記号は `catalog.contains` で存在確認)。理由は「中身の多くが%@ (%lld 件)」。
- `content?.representative` があれば `.image` チップを **末尾** に足す。理由は「中身の画像「%@」」(ファイル名)。
- 上限 4 (記号・絵文字・文字・画像)。既存の `suggest(for:presets:)` は `content: nil` で同じ結果を返す (既存テストはそのまま通る)。

### 5.3 画面と状態

- `SuggestionStripView`: チップのラベルは `.frame(maxWidth: 120)` + `lineLimit(1)` + `.truncationMode(.middle)`。帯全体を `ScrollView(.horizontal, showsIndicators: false)` に入れ、4 つ入らなくても右へはみ出さない。高さ 36pt は変えない。
- `.image` チップのサムネイル: `thumbnailPNG` から `NSImage` を作り、`OverlayRenderer.render(image:side:)` (画像の経路を `static` に公開) → `IconComposer.compose` で他のチップと同じ「フォルダに合成した見た目」にする。
- `AppModel`:
  - 名前からの候補は今までどおり同期で即時 (`CombineLatest3`)。
  - 中身は **`suggestionSourceFolder` が変わったときだけ** 走査する。走査ごとに単調増加の `scanGeneration` を振り、`Task.detached(priority: .utility)` で `scan` → `thumbnailPNG` を実行し、戻った時点で **generation が最新で、かつ `suggestionSourceFolder` が同じ URL** のときだけ結果を `contentSummary` に入れて候補を作り直す。どちらかが違えば捨てる (同じ URL を外して入れ直した場合も、新しい generation の結果だけを採る)。走査中に対象が変わったら前の `Task` を `cancel()` する。cancel は best effort (列挙のループでは効くが、`CGImageSource` の 1 枚分は途中で止まらない)。古い結果を採らないことは generation で保証する。
  - お気に入りの変化では再走査しない (`contentSummary` を使い回す)。対象が nil になったら `contentSummary` を消す。
  - 走査関数はテストのために注入できる (`scanner: @Sendable (URL) -> ContentSummary?`)。
- 採用: `.image` → 既存の `selectImage(url)` (ドロップと同じ経路。`AssetStore` に 512px PNG で複製し画像タブへ)。記号・絵文字・文字・お気に入りは現行どおり。
- サンドボックス: `NSOpenPanel` とドロップで受け取った URL の権限はプロセスの寿命の間有効で、スレッドや URL 値には紐づかない (現行の一括適用も、受け取った後に別スレッドで書き込んでいる)。履歴から戻したフォルダは `folderURL(for:)` がリストにある間スコープを開いたままにしている。したがって走査と `.image` の採用 (`selectImage`) に新しい権限や `startAccessingSecurityScopedResource` は要らない。走査中にリストから外されてスコープが閉じた場合は読めずに nil になるが、その結果は対象が変わっているので捨てられる。

### 5.4 テスト

- `ContentScannerTests` (一時ディレクトリに拡張子だけのダミーと小さな実 PNG を置く): 多数派の判定、同数のときの列挙順、隠しファイルと `Icon\r` の除外、サブフォルダは `folder` に数える、`dominant == .folder` で代表画像なし、代表画像は更新日時が最新、`heic` 以外の非対応形式 (`psd` など) と `maxImageBytes` 超は代表にしない、`limit` で打ち切る (件数の合計が `limit`)、存在しないパスは nil、サムネイル PNG の長辺が 256 以下、EXIF で 90 度回転した 2:1 の JPEG (`CGImageDestination` で orientation 6 を付けて作る) のサムネイルは縦長になる。
- `SuggestionEngineTests` (追加分): 名前が当たれば中身は空枠だけ埋める、名前が空でも中身だけで記号・絵文字が出る、`folder` が多数派なら出ない、代表画像があれば 4 つ目に `.image`、`content: nil` は従来と同じ。
- `SuggestionDictionaryTests`: `entry(forKey:)` が代表キーを引ける (全 `ContentKind` について。`folder` は除く)。
- `AppModelTests`: 注入した scanner (結果を返すタイミングを制御できるもの) で、走査が戻る前に対象フォルダを変えたら古い generation の結果を捨てる、同じフォルダのままなら候補に `.image` が足される、同じフォルダを外して入れ直したら新しい generation で走査し直す、cancel された走査の結果は採らない、お気に入りを足しても再走査しない (呼び出し回数)。代表画像が消えた後にチップを押すと `selectImage` の既存アラートになる (§7)。

## 6. 画面と状態のまとめ

- 新規: `Services/FontCatalog.swift`、`Services/ContentScanner.swift`、`Services/AppLanguage.swift` (`AppLanguage` + `LanguageSetting`)、`Resources/Localizable.xcstrings`、`Resources/InfoPlist.xcstrings`。
- 変更: `Services/OverlayRenderer.swift` (`makeFont` → `FontCatalog`、`render(image:side:)` の公開)、`Models/CodableColor.swift` (`FontWeightValue.displayName`)、`Models/Suggestion.swift` (`.image`)、`Services/SuggestionEngine.swift` (`content:`)、`Services/SuggestionDictionary.swift` (`entry(forKey:)`)、`Resources/suggestions.json` (presentation / spreadsheet)、`Views/ControlsView.swift` (2 行)、`Views/SuggestionStripView.swift` (横スクロール、`.image` チップ)、`AppModel.swift` (中身の走査)、`FolderArtApp.swift` (言語メニュー、`LanguageSetting`)、`ContentView.swift` (`showsFont` / `showsWeight`、再起動アラート、高さ)、§4.2 の 5 ファイル、`project.yml` (1.4.0 / ビルド 7、`developmentLanguage`、ビルド設定)。
- 文言はすべて `Text("…")` / `String(localized:)`。新しい文言も最初からカタログに 8 言語分入れる。

## 7. エラー処理

| 事象 | 扱い |
|------|------|
| フォントの家族がこの Mac に無い | 既定 (丸ゴシック) で描く。Picker には「その他 (名前)」を出す。アラートは出さない |
| 言語の保存に失敗 (UserDefaults) | 実質起きない。再起動に失敗したら終了せずアラート |
| 適用中に言語を変えた | 保存だけ行い、[再起動] を出さない。次回起動で反映 |
| フォルダの中身が読めない (権限・消えた・ネットワーク断) | 中身の候補なし。アラートは出さない。名前からの候補はそのまま |
| 代表画像が読めない・巨大 | 代表画像なし (種類の候補は出す) |
| 走査が遅い (ネットワークボリューム) | 非同期 + 上限 1000 件。対象が変われば cancel |
| 画像チップの採用で複製に失敗 | 既存の `selectImage` と同じアラート |

## 8. README とメイン画像

- 機能一覧 (日英併記) に「文字のフォントと太さ」「8 言語対応と言語メニュー」「フォルダの中身からの提案 (種類と代表画像)」を追記。
- プロジェクト構成に §6 の新規ファイルを追加。
- `docs/images/main.png` を 1.4.0 の画面 (フォント・太さの行、提案の帯に画像チップ) で撮り直す。撮影は第2段階と同じ自動化 (`screencapture` の CGWindowID 指定) で Retina 2x、幅 1520px 程度。
- 動作環境は変えない (macOS 13+)。

## 9. テスト方針の要約

新規テストは §3.4、§4.4、§5.4。既存テストは維持 (言語に依存しない書き方に 1 件だけ直す)。UI は実機で確認: フォントと太さの切り替えとプレビュー、他タブでの無効表示、言語メニューで英語を選んで再起動、「システムに従う」で戻る、画像の多いフォルダで画像チップ、クリックで画像タブに入る、4 チップが帯に収まる。

## 10. 影響を受ける既存ファイル

| ファイル | 変更 |
|----------|------|
| `Services/OverlayRenderer.swift` | `makeFont` を `FontCatalog.font` に委譲、`render(image:side:)` を公開 |
| `Models/CodableColor.swift` | `FontWeightValue.displayName` |
| `Models/Suggestion.swift` | `.image(url:thumbnailPNG:)`、等価判定と id |
| `Services/SuggestionEngine.swift` | `suggest(for:presets:content:)` |
| `Services/SuggestionDictionary.swift` | `entry(forKey:)` |
| `Resources/suggestions.json` | presentation / spreadsheet の項目 |
| `Views/ControlsView.swift` | フォント・太さの 2 行、`showsFont` / `showsWeight`、三項演算子の修正 |
| `Views/SuggestionStripView.swift` | 横スクロール、ラベル幅、`.image` チップ |
| `Views/DropZoneView.swift` | `buttonLabel` を `LocalizedStringKey` に |
| `Services/BookmarkManager.swift`, `Services/ApplyCoordinator.swift` | 文言を `String(localized:)` に |
| `AppModel.swift` | 中身の走査 (`contentSummary`、cancel、注入)、既定ファイル名の文言 |
| `FolderArtApp.swift` | 言語メニュー、`LanguageSetting`、`defaultSize` |
| `ContentView.swift` | `showsFont` / `showsWeight`、再起動アラート、`minHeight` |
| `project.yml` | 1.4.0 / ビルド 7、`developmentLanguage: en`、`LOCALIZATION_PREFERS_STRING_CATALOGS`、`SWIFT_EMIT_LOC_STRINGS` |
| `FolderArtTests/ApplyCoordinatorTests.swift` | `contains` を `String(localized:)` に |
| `README.md` | 機能一覧、構成、画像 |
