# 第6段階 実装計画 — 複数解像度アイコン・サービス名の他言語化・提案の精度改善・ツール整備

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** アイコン適用を複数解像度にし、クイックアクション名を他言語化し、提案の精度を上げ、文言ツールと監視の残件を片付ける。

**Architecture:** 4 領域は独立。V=IconComposer/ApplyCoordinator、L=localization 生成、S=SuggestionEngine/ContentScanner/suggestions.json、T=build-xcstrings.py/AppModel。既存設計を尊重し加える/締める。

**Tech Stack:** Swift 5.9, SwiftUI+AppKit, XcodeGen, XCTest, Python 3。macOS 13。

**Spec:** `docs/superpowers/specs/2026-09-06-multires-i18n-suggestions-design.md`

## Global Constraints
- macOS 13.0 / Swift 5.9 (非 strict concurrency)。新規依存なし。
- **`xcodebuild` は必ずフォアグラウンド + `timeout: 600000`。バックグラウンド禁止。**
- 全テスト: `xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"`。プロジェクト由来 warning 0。`appintentsmetadataprocessor` と意図的な `*** ERROR: CGImageSourceCreateThumbnailAtIndex … failed` は無視。
- 新規ファイルを作る Task は `xcodegen generate` して pbxproj をコミットに含める。
- 文言は `strings.json`/`infoplist.json`/(新)`servicesmenu.json` から `build-xcstrings.py` で生成。8 言語 (ja/en/de/es/fr/ko/pt-BR/zh-Hant、ja==キー)。`--check` missing 0。
- コミット本文末尾は必ず:
  ```
  Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- main/develop 直コミット禁止 (作業ブランチ `feature/multires-i18n-suggestions`)。バージョンは Task 9 で 1.7.0 / 10。

## File Structure
- Modify `FolderArt/Services/IconComposer.swift` (compose に side、composeMultiResolution 追加、doc)
- Modify `FolderArt/Services/ApplyCoordinator.swift` (compose→composeMultiResolution)
- Modify `FolderArt/Services/SuggestionEngine.swift` (S1/S2)
- Modify `FolderArt/Services/ContentScanner.swift` + `FolderArt/Services/SuggestionDictionary.swift` (S3: 新 ContentKind、代表画像フィルタ)
- Modify `FolderArt/Resources/suggestions.json` (S4)
- Modify `scripts/localization/build-xcstrings.py` (T1 指定子検出、L 3rd target)
- Create `scripts/localization/servicesmenu.json` + `FolderArt/Resources/ServicesMenu.xcstrings` (L)
- Modify `scripts/localization/infoplist.json` + `FolderArt/Resources/InfoPlist.xcstrings` (L: サービス名エントリ削除)
- Modify `FolderArt/AppModel.swift` (T2 内容ハッシュ再読込)
- Modify `project.yml` (Task 9 バージョン)、`README.md` (Task 9)
- Tests: `FolderArtTests/IconComposerTests.swift`, `SuggestionEngineTests.swift`, `ContentScannerTests.swift`, `AppModelTests.swift`, `scripts/localization/` python の手動確認

---

### Task 1: 複数解像度アイコン (V)

**Files:**
- Modify: `FolderArt/Services/IconComposer.swift`
- Modify: `FolderArt/Services/ApplyCoordinator.swift:54`
- Test: `FolderArtTests/IconComposerTests.swift`

**Interfaces:**
- Consumes: `BitmapCanvas.draw(size:_:) -> NSImage?`、`standardFolderIcon: NSImage`、`calculateRect(for:in:settings:fillsWhenClipped:)`、`ApplyCoordinator.apply(overlayImage:overlay:settings:to:progress:)`。
- Produces: `IconComposer.compose(overlay:settings:base:fillsWhenClipped:side:)` (side 既定 iconSize.width)、`IconComposer.composeMultiResolution(overlay:settings:base:fillsWhenClipped:) -> NSImage?`。

- [ ] **Step 1: compose を任意サイズ対応にするテスト**

`IconComposerTests.swift` に追記:
```swift
func testComposeAtCustomSideProducesThatPixelSize() {
    let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
    let img = IconComposer.compose(overlay: overlay, settings: CompositionSettings(), fillsWhenClipped: false, side: 32)
    let rep = try! XCTUnwrap(img?.representations.first)
    XCTAssertEqual(rep.pixelsWide, 32); XCTAssertEqual(rep.pixelsHigh, 32)
}
```

- [ ] **Step 2: 落ちる確認** — `-only-testing:FolderArtTests/IconComposerTests`。Expected: コンパイル失敗 (side 引数なし)。

- [ ] **Step 3: compose に side を足す**

`IconComposer.compose` を次に変更 (既存本体はサイズ変数を `side` から作る):
```swift
static func compose(
    overlay overlayImage: NSImage,
    settings: CompositionSettings,
    base: NSImage = standardFolderIcon,
    fillsWhenClipped: Bool,
    side: CGFloat = iconSize.width
) -> NSImage? {
    let size = CGSize(width: side, height: side)
    let overlayRect = calculateRect(for: overlayImage.size, in: size, settings: settings, fillsWhenClipped: fillsWhenClipped)
    return BitmapCanvas.draw(size: size) { _ in
        base.draw(in: NSRect(origin: .zero, size: size), from: NSRect(origin: .zero, size: base.size), operation: .sourceOver, fraction: 1)
        // …既存の clip/描画本体はそのまま (size を使う)…
    }
}
```
既存の呼び出し (side 省略) は 512 のまま動く。

- [ ] **Step 4: composeMultiResolution のテスト**

```swift
func testComposeMultiResolutionHasBaseRepSizes() throws {
    let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
    let img = try XCTUnwrap(IconComposer.composeMultiResolution(overlay: overlay, settings: CompositionSettings(), fillsWhenClipped: false))
    let sizes = Set(img.representations.map { $0.pixelsWide })
    let baseSizes = Set(IconComposer.standardFolderIcon.representations.map { $0.pixelsWide })
    XCTAssertFalse(sizes.isEmpty)
    XCTAssertEqual(sizes, baseSizes)   // 土台の表現サイズ集合と一致
    for rep in img.representations { XCTAssertEqual(rep.pixelsWide, rep.pixelsHigh) }
}
```

- [ ] **Step 5: composeMultiResolution を実装**

```swift
/// 標準フォルダーアイコンの各表現ピクセルサイズごとに 1 枚ずつ合成し、複数表現の NSImage を返す。
/// overlay は各サイズへ高品質縮小され、土台は各サイズの native 表現を使うので小サイズでも鮮明。
/// 表現が無い土台では 512px 一枚にフォールバック。
static func composeMultiResolution(
    overlay overlayImage: NSImage,
    settings: CompositionSettings,
    base: NSImage = standardFolderIcon,
    fillsWhenClipped: Bool
) -> NSImage? {
    let sizes = Set(base.representations.map { $0.pixelsWide }).filter { $0 > 0 }
    guard !sizes.isEmpty else {
        return compose(overlay: overlayImage, settings: settings, base: base, fillsWhenClipped: fillsWhenClipped)
    }
    let out = NSImage(size: iconSize)
    for px in sizes.sorted() {
        guard let one = compose(overlay: overlayImage, settings: settings, base: base,
                                fillsWhenClipped: fillsWhenClipped, side: CGFloat(px)),
              let rep = one.representations.first else { continue }
        out.addRepresentation(rep)
    }
    return out.representations.isEmpty ? nil : out
}
```
注: `compose(side: px)` は `base.draw(in: size)` で土台を px にスケールする。土台 NSImage は要求サイズに最も近い表現を使うので、px=32 の描画では土台の 32px 表現が使われ鮮明。

- [ ] **Step 6: ApplyCoordinator を複数解像度に**

`ApplyCoordinator.apply` の `IconComposer.compose(overlay: overlayImage, settings: settings, fillsWhenClipped: overlay.fillsFolderWhenClipped)` を `IconComposer.composeMultiResolution(overlay: overlayImage, settings: settings, fillsWhenClipped: overlay.fillsFolderWhenClipped)` に差し替える。失敗時のフォールバック (compose 失敗と同じ扱い) は維持。プレビュー経路 (OverlayState) は変更しない (512 のまま)。

- [ ] **Step 7: IconComposer の doc に 512 明記 (T3 の一部)**

`IconComposer` 冒頭 or `iconSize` に「基準は 512px。アイコン適用時は composeMultiResolution が土台の各表現サイズで描く」と 1 行。

- [ ] **Step 8: テスト**

Run: 全体スイート (フォアグラウンド)。Expected: `Executed <N> tests, with 0 failures`、warning 0。既存 IconComposer テスト維持。

- [ ] **Step 9: コミット**

```
feat: ✨ アイコン適用を複数解像度にする (土台の各表現サイズごとに合成)
```

---

### Task 2: 提案の誤検出減 + ランク改善 (S1/S2)

**Files:**
- Modify: `FolderArt/Services/SuggestionEngine.swift`
- Test: `FolderArtTests/SuggestionEngineTests.swift`

**Interfaces:**
- Consumes: `dictionary.entries`, `catalog.contains`, `catalog.names(forTerm:)`, `normalize`, `latinTokens`。
- Produces: `SuggestionEngine.stopWords` (static set)、更新された `nameSuggestions`。

- [ ] **Step 1: テストを書く** (`SuggestionEngineTests.swift`)

```swift
// S1: 1 文字の日本語辞書キーは部分一致しない
func testSingleCharJapaneseKeyDoesNotMatch() { /* 辞書に 1 文字キー項目、フォルダ名にそれを含む → 記号提案されない */ }
// S1: Latin の曖昧 SF 検索は 4 文字以上のみ
func testFuzzySymbolSearchRequiresFourChars() { /* 3 文字トークンで names(forTerm:) 経路に入らない */ }
// S1: stop-word は曖昧一致しない
func testStopWordNotFuzzyMatched() { /* "work" 単独では曖昧 SF 検索しない */ }
// S2: まるごと一致が長い部分一致より優先
func testWholeNameMatchRanksFirst() { /* 「写真」完全一致が、より長い別キーの部分一致より symbol 枠を取る */ }
```
(具体値は実装後の辞書/カタログに合わせて実装者が確定。テスト用に小さな `SuggestionDictionary(entries:)` と `SymbolCatalog` スタブ/実物を使う。)

- [ ] **Step 2〜4: 落ちる確認 → 実装 → 通す**

`SuggestionEngine` に:
```swift
static let stopWords: Set<String> = ["new","old","my","the","and","for","temp","tmp","misc","other","data","file","files","folder","backup","download","downloads","work","test","project","その他","新規","一時","資料"]
```
`nameSuggestions` を次のように締める/並べ替える:
- 辞書ループの一致判定: Latin は `tokens.contains(key)` のまま。日本語 (非 Latin) は `key.count >= 2 && normalized.contains(key)` に (1 書記素キーを弾く)。
- `hits` に `isWholeMatch` を持たせる: `key == normalized || tokens.contains(where: { $0 == key })` のとき true。ソートを `(isWholeMatch, key.count, -position)` の降順に。
- 第3層 (SF 検索): `catalog.contains(token)` は `token.count >= 3` のまま。曖昧 `catalog.names(forTerm: token).first` は `token.count >= 4 && !Self.stopWords.contains(token)` のときだけ。
- stop-word は「規則的な曖昧一致」(第3層) と「非 Latin 部分一致でキーが stop-word のとき」に効かせる。辞書に明示キーとして入っている語の一致には効かせない (明示辞書はそのまま)。

- [ ] **Step 5: コミット** — `fix: 🎯 提案の誤検出を減らし、名前まるごと一致を優先する`

---

### Task 3: 中身の種類判定強化 (S3)

**Files:**
- Modify: `FolderArt/Services/ContentScanner.swift` (ContentKind に ebook/font/model、classify、代表画像フィルタ)
- Test: `FolderArtTests/ContentScannerTests.swift`

**Interfaces:**
- Produces: `ContentKind.ebook/.font/.model` + それぞれの `dictionaryKey`/`reason`。`classify` の対応追加。代表画像で長辺 < 64px を除外。

- [ ] **Step 1: テスト**
```swift
func testClassifyEbookFontModel() {
    XCTAssertEqual(ContentScanner.classify(type: .epub, isDirectory: false, isPackage: false), .ebook)
    XCTAssertEqual(ContentScanner.classify(type: .font, isDirectory: false, isPackage: false), .font)
    XCTAssertEqual(ContentScanner.classify(type: UTType("public.3d-content"), isDirectory: false, isPackage: false), .model)
}
```
(代表画像 64px フィルタは ContentScanner の scan テストで、64px 未満の画像だけのフォルダでは representative が nil になることを確認。)

- [ ] **Step 2〜4: 実装**
- `ContentKind` に `case ebook, font, model` を追加 (image..app の後、archive/app の並びは維持しつつ「具体的種類を先、document を後」)。
- `dictionaryKey`: ebook→`"ebook"`, font→`"font"`, model→`"model"` (suggestions.json にこれらのキーを Task 5 で用意)。`reason`: 「中身の多くが電子書籍 (…)」等 (8 言語は文言化 — `String(localized:)`、Task 5/9 で strings.json に追加)。
- `classify` に: `.epub`/`com.amazon.ebook`/`org.idpf.epub-container`→ebook、`.font`→font、`public.3d-content`/`.usd`/`.sceneKitScene`→model を、既存判定の適切な位置 (application/image より後、document より前) に追加。
- 代表画像: `ContentScanner` の代表選択で、画像の長辺が 64px 未満のものを候補から除外 (CGImageSource でサイズを見る既存経路に閾値を足す)。

- [ ] **Step 5: コミット** — `feat: 🎯 中身の種類に電子書籍・フォント・3D を追加し、極小画像を代表から除く`

---

### Task 4: 提案辞書の語彙と他言語キー (S4)

**Files:**
- Modify: `FolderArt/Resources/suggestions.json`
- Test: `FolderArtTests/SuggestionEngineTests.swift` (他言語キー一致 1〜2 件)

- [ ] **Step 1: テスト** — 追加した他言語キー (例 de "rechnungen"、fr "photos" は既存) でフォルダ名に一致し記号/絵文字提案が出ることを 1〜2 件。
- [ ] **Step 2: suggestions.json 更新**
  - 各既存項目に de/es/fr/ko/pt-BR/zh-Hant のキーを追加 (自然な語、小文字)。
  - 新項目を追加 (請求書/領収書=`doc.text`/🧾、契約=`signature`/✍️、履歴書、旅行=`airplane`/✈️、レシピ=`fork.knife`/🍳、ゲーム=`gamecontroller.fill`/🎮、壁紙=`photo.on.rectangle.angled`/🖼️、電子書籍=`book.fill`/📚 [ebook キー]、フォント=`textformat`/🔤 [font キー]、3D=`cube.fill`/🧊 [model キー] 等)、各 8 言語キー。
  - ebook/font/model は Task 3 の `dictionaryKey` (`"ebook"/"font"/"model"`) を keys に含める。
- [ ] **Step 3: テスト** — 全体スイート。`suggestions.json` は JSON として妥当 (SuggestionDictionary.load が読める)。
- [ ] **Step 4: コミット** — `feat: 🌐 提案辞書に他言語キーと語彙を追加する`

---

### Task 5: --check の指定子型不一致検出 (T1)

**Files:**
- Modify: `scripts/localization/build-xcstrings.py`
- Test: 手動 (python を直接叩く。レポートに出力を貼る)

- [ ] **Step 1: 実装**
`build-xcstrings.py` に指定子抽出を足す:
```python
import re
def specifiers(key):
    # %% を除き、%[flags][width][length]conv を順に取り出して型記号列にする
    return re.findall(r'%(?:\d+\$)?[-+ 0#]*\d*(?:\.\d+)?(?:ll|l|h|hh|q|z|t|j|L)?[@dioux XeEfFgGaAcspn%]', key.replace('%%',''))
```
`check()` (正規表現 --check) と `check_compiled()` の両方で、strings.json のキー集合とコード側キー集合を突き合わせる際、**同じ「指定子を除いた骨格」を持つが指定子列が違う**キーの組を検出し `specifier mismatch: <code key> vs <json key>` を出して exit 1。実装しやすい形: コード側キーそれぞれについて、strings.json に完全一致が無く、かつ「%… を除いた文字列」が一致する json キーがあれば不一致として報告。

- [ ] **Step 2: 動作確認**
`strings.json` に既存キーの指定子を一時的に変えたコピーで `specifier mismatch` が出て exit 1、元では出ないことを確認 (一時変更は戻す)。既存 `--check` の missing 判定は不変。
- [ ] **Step 3: コミット** — `chore: 🔧 文言チェックに指定子の型不一致検出を追加する`

---

### Task 6: FileWatcher の内容ハッシュ再読込 (T2)

**Files:**
- Modify: `FolderArt/AppModel.swift`
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `performDictionaryReload`、`Self.dictionaryErrorFingerprint`、`SuggestionDictionary.loadUser`。
- Produces: `lastLoadedDictionaryHash: Data?` による無変化スキップ。

- [ ] **Step 1: テスト**
```swift
// 内容が同じままディレクトリに無関係な書き込みが起きても、エンジンが作り直されない
func testReloadSkipsWhenDictionaryContentUnchanged() throws { /* 同じ内容で 2 回 reload → 2 回目は suggestionEngine インスタンスが変わらない (===) こと */ }
// 内容が変わったら作り直される
func testReloadRebuildsWhenDictionaryContentChanged() throws { /* 内容変更後の reload で提案が変わる */ }
```
(`suggestionEngine` の同一性を見るため、テスト用に `private(set)` を利用。`===` 比較できるよう SuggestionEngine が class であることを確認 — class なら OK。)

- [ ] **Step 2〜4: 実装**
`performDictionaryReload` を、読み込んだ**ファイル内容のハッシュ**で早期 return するよう変更:
- detached 内で、成功/nil/失敗いずれでも「現在のファイル内容のハッシュ (無ければ nil を表す固定値)」を計算して返す。
- 世代ガードの後、`contentHash == lastLoadedDictionaryHash` なら **エンジンを作り直さず** return (提案の再計算もしない)。違えば従来どおり作り直し、`lastLoadedDictionaryHash = contentHash` を更新。
- 壊れたファイルのアラート判定 (`lastDictionaryErrorHash`、内容ごとに 1 回) は現状維持。無変化スキップと両立させる (内容が同じ壊れファイルは 2 回目スキップで自然に無音)。
- ハッシュは「ファイルが無い」も 1 状態として区別 (nil ではなく固定センチネル、例: 空データの SHA-256)。

- [ ] **Step 5: コミット** — `perf: ⚡ 提案辞書は内容が変わった時だけ読み直す (無関係な保存での再計算を止める)`

---

### Task 7: サービス名の他言語化 (L)

**Files:**
- Create: `scripts/localization/servicesmenu.json`, `FolderArt/Resources/ServicesMenu.xcstrings`
- Modify: `scripts/localization/build-xcstrings.py` (TARGETS に 3 つ目)、`scripts/localization/infoplist.json` + `FolderArt/Resources/InfoPlist.xcstrings` (サービス名エントリ削除)

- [ ] **Step 1: build-xcstrings.py の TARGETS に追加**
```python
TARGETS = [
    ("strings.json", "FolderArt/Resources/Localizable.xcstrings"),
    ("infoplist.json", "FolderArt/Resources/InfoPlist.xcstrings"),
    ("servicesmenu.json", "FolderArt/Resources/ServicesMenu.xcstrings"),
]
```
- [ ] **Step 2: servicesmenu.json** — キー = 日本語メニュー名、値 8 言語 (InfoPlist に入れてある既存訳を移す):
```json
{
  "FolderArt で開く": ["FolderArt で開く", "Open in FolderArt", "In FolderArt öffnen", "Abrir en FolderArt", "Ouvrir dans FolderArt", "FolderArt에서 열기", "Abrir no FolderArt", "在 FolderArt 中打開"],
  "FolderArt で直前のお気に入りを適用": ["…8 言語…"],
  "FolderArt でアイコンを元に戻す": ["…8 言語…"]
}
```
- [ ] **Step 3: 生成 + InfoPlist からサービス名を除去**
`python3 scripts/localization/build-xcstrings.py` で `ServicesMenu.xcstrings` 生成。`infoplist.json` からサービス名 3 キーを削除し `FolderArt Preset Pack` だけ残す → 再生成で `InfoPlist.xcstrings` からも消える。`xcodegen generate` (新規リソースを含める)。`--check` は従来どおり missing 0 (ServicesMenu はコード文言でないので対象外)。
- [ ] **Step 4: 全体テスト** — `Executed <N> tests`。ServicesMenu 追加でテストは増えない。
- [ ] **Step 5: コミット** — `feat: 🌐 クイックアクション名を ServicesMenu.strings で 8 言語化する`
- [ ] **Step 6: 実機検証 (コントローラー)** — Release ビルド → `.app/Contents/Resources/en.lproj/ServicesMenu.strings` が生成されているか、英語でアプリを起動・登録し Finder のクイックアクション名が英語になるかを確認。通らなければ ServicesMenu を撤回し日本語据え置き (spec の見送り条項) にして記録。

---

### Task 8: バージョン・README・仕上げ (コントローラー)

**Files:** `project.yml`, `README.md`

- [ ] **Step 1: バージョン** — `MARKETING_VERSION: 1.7.0` / `CURRENT_PROJECT_VERSION: 10`。`xcodegen generate`。
- [ ] **Step 2: README (日英併記)** — 機能一覧に「複数解像度アイコンで小サイズでも鮮明」「クイックアクション名の多言語対応 (検証結果次第)」、提案の改善を 1 行。`check-compiled.sh` 等の構成は既存のまま。
- [ ] **Step 3: 全テスト + --check + check-compiled.sh** — すべて成功・missing 0。
- [ ] **Step 4: コミット** — `chore: 🔖 1.7.0 に更新し README を整える`
- [ ] **Step 5: 仕上げ (コントローラー)** — 実機確認 (アイコンが小サイズで鮮明、提案が改善、サービス名の言語追従) → Codex 事前レビュー (フォアグラウンド) → PR (日英併記) → Codex 対応 → ユーザー確認後マージ → main 同期 → Release v1.7.0 → アプリ入れ替え。

---

## Self-Review (計画者チェック)
- spec カバレッジ: V=Task1、L=Task7、S1/S2=Task2、S3=Task3、S4=Task4、T1=Task5、T2=Task6、T3(doc)=Task1 Step7 + Task5、バージョン/README=Task8。全網羅。
- 型整合: `compose(...,side:)`、`composeMultiResolution(overlay:settings:base:fillsWhenClipped:)`、`ContentKind.ebook/.font/.model`、`stopWords`、`lastLoadedDictionaryHash`、servicesmenu.json→ServicesMenu.xcstrings。実コードと一致。
- 依存順: Task 3 (ContentKind.dictionaryKey) と Task 4 (suggestions.json のキー) は連携 — Task 3 が dictionaryKey を定義し、Task 4 がその語を辞書に入れる。Task 4 は Task 3 の後。Task 2 と Task 4 はどちらも SuggestionEngineTests に触るので順に。
- リスク: L (ServicesMenu) は実機検証必須・不可なら撤回 (Task 7 Step 6)。V の負荷は許容 (プレビューは 512 のまま)。
