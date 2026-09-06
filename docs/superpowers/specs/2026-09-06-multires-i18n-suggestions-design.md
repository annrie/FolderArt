# FolderArt 第6段階 設計 — 複数解像度アイコン・サービス名の他言語化・提案の精度改善・ツール整備

**日付:** 2026-09-06
**対象バージョン:** 1.7.0 / ビルド 10
**前段階:** 1.6.0 (第5段階、PR #6/#7、Finder クイックアクション)

4 つの独立した領域を 1 段階にまとめる。各領域は個別にテスト・レビュー・(必要なら) 単独リリースできる粒度で設計する。

---

## V. 複数解像度アイコン / Multi-resolution icons

### 現状
`IconComposer.compose(overlay:settings:base:fillsWhenClipped:)` が 512px 一枚の `NSImage` を作り、`FolderIconManager` が `NSWorkspace.setIcon(_:forFile:)` で適用する。小サイズ (Finder のリスト/カラム/サイドバー) では macOS が 512px を縮小するため、細い記号や文字がぼやけ、フォルダー地色も純正の小サイズ表現より甘くなる。

### 設計
標準フォルダーアイコン (`NSWorkspace.shared.icon(forFile:)`) は 16〜1024px の複数 `NSImageRep` を持つ。その**各表現のピクセルサイズごとに**オーバーレイを再描画して合成し、複数表現を持つ 1 枚の `NSImage` を作って適用する。

- `IconComposer.compose(...)` は「指定 1 サイズの合成」の原始関数のままにし (既存の `side`/`iconSize` 経路を維持)、新たに:
  ```swift
  /// 標準フォルダーアイコンの各表現サイズごとにオーバーレイを合成し、複数表現の 1 枚を返す。
  /// overlay は各サイズで OverlayRenderer.render(side:) を呼び直して鮮明に描く。
  static func composeMultiResolution(overlay: NSImage, settings: CompositionSettings,
                                     base: NSImage = standardFolderIcon,
                                     fillsWhenClipped: Bool) -> NSImage?
  ```
  実装: `base.representations` の各 rep について `rep.pixelsWide × rep.pixelsHigh` を取り、そのピクセルサイズで 1 枚合成 (`BitmapCanvas` に px 指定で描く)、得たビットマップ (`NSBitmapImageRep`) を集めて 1 つの `NSImage` に addRepresentation する。重複サイズは 1 回だけ。表現が 1 つも無い土台の場合は従来どおり 512px 一枚にフォールバック。
- **オーバーレイの再描画**: `applyLastPreset`/`apply` の呼び出し側は今 `OverlayRenderer.render(side: IconComposer.iconSize.width)` で 512px の overlay 画像を作って渡している。複数解像度では、合成側が各サイズで overlay を描き直す必要がある。そこで `composeMultiResolution` は「overlay の**元 (Overlay + settings)**」からサイズごとに `OverlayRenderer.render(_:settings:side:assets:)` を呼べるよう、overlay 画像ではなく **`Overlay` 値と `AssetStore`** を受け取る版も用意する:
  ```swift
  static func composeMultiResolution(overlay: Overlay, settings: CompositionSettings,
                                     assets: AssetStore, base: NSImage = standardFolderIcon) -> NSImage?
  ```
  画像オーバーレイ (`.image`/代表画像) は元が固定画素なので、各サイズには高品質縮小 (`OverlayRenderer.render(image:side:)`) を使う。記号・絵文字・文字は各サイズで描き直す。
- `ApplyCoordinator.apply(...)` と `AppModel.applyLastPreset` は、512px 一枚ではなく `composeMultiResolution` の結果を `FolderIconManager` に渡すよう差し替える。`FolderIconManager.applyIcon` は `NSImage` を受け取るso変更不要。
- **負荷**: 一括適用では 1 フォルダーにつき最大 7 サイズ (16/32/64/128/256/512/1024) を合成する。`BitmapCanvas` の描画は高速だが、多数フォルダーで無駄がないよう「土台アイコンは 1 回取得して使い回す」「代表画像の縮小は 1 回だけ元画像から」を守る。プレビュー (ウィンドウ内) は従来どおり 512px 一枚でよい (アイコン適用時のみ複数解像度)。

### テスト
- `composeMultiResolution` の結果 `NSImage` が、土台の表現ピクセルサイズ集合と同じサイズの表現を持つ (例: 16/32/64/128/256/512/1024 のうち土台が持つもの)。
- 各サイズの表現が実際にそのピクセルサイズ (`rep.pixelsWide`) を持つ。
- 記号オーバーレイで、32px 表現が「512px を縮小したもの」ではなく 32px で描かれている (代理として: 32px 合成の結果が `compose(side: 32)` と一致する)。
- 表現が空の土台ではフォールバックで 512px 一枚になる。
- リセット (`setIcon(nil)`) は従来どおり動く (既存テスト維持)。

---

## L. サービス名の他言語化 / Localized service names

### 現状
第5段階でクイックアクションのメニュー名 (`FolderArt で開く` ほか) を `InfoPlist.xcstrings` に 8 言語で入れたが、Finder は NSServices のタイトルを `InfoPlist.strings` ではなく **`ServicesMenu.strings`** テーブルから localize するため、日本語以外では日本語の既定名にフォールバックする (第5段階で判明、見送り)。

### 設計
- `FolderArt/Resources/ServicesMenu.xcstrings` (テーブル名 `ServicesMenu`) を新設し、**キー = 現在の日本語メニュー名** (`FolderArt で開く` / `FolderArt で直前のお気に入りを適用` / `FolderArt でアイコンを元に戻す`)、値を 8 言語で持つ。Xcode が各 `*.lproj/ServicesMenu.strings` にコンパイルし、Finder はそこからタイトルを localize する。
- 生成は既存の `scripts/localization/build-xcstrings.py` に 3 つ目の TARGET を足す: `servicesmenu.json` → `FolderArt/Resources/ServicesMenu.xcstrings`。`servicesmenu.json` の形は既存 (キー → 8 言語) と同じ。翻訳は InfoPlist に入れた既存のサービス名訳を流用する (各言語に「FolderArt」を含む自然な訳)。
- `InfoPlist.xcstrings` のサービス名エントリは Finder では無効なので**削除**し、`infoplist.json` からも外す (混乱と死に設定を避ける)。書類の種類名 (`FolderArt Preset Pack`) は残す。
- Info.plist の `NSServices` の `NSMenuItem.default` は日本語名のまま (ServicesMenu.strings のキーになる)。

### リスク・検証
String Catalog 由来の `ServicesMenu.strings` を Finder が実際に読むかは、システム言語を変えた実機でしか確認できない。**コントローラーが検証する**: (1) ビルド後の `.app/Contents/Resources/<lang>.lproj/ServicesMenu.strings` が生成されているか、(2) 別言語 (例: 英語) でアプリを起動・登録し Finder のクイックアクション名が英語になるか。**通らなければ**、`ServicesMenu.xcstrings` を諦め、日本語の自己識別名のまま据え置き (第5段階と同じ) にして spec の受け入れ条件から外し、その旨を記録する。

### テスト
- `build-xcstrings.py` が `ServicesMenu.xcstrings` を生成し、`--check` は従来どおり通る (この表はコード内文言ではないので `--check`/`--stringsdata` の対象外で問題ない)。
- 実機目視 (コントローラー): 別言語でメニュー名が追従するか、または追従しないことを確認し記録。

---

## S. 提案の精度改善 + 辞書の他言語キー / Suggestion accuracy

既存 `SuggestionEngine` の 4 層 (お気に入り → 辞書 → SF 検索 → 規則) と `ContentScanner` を尊重し、次の 4 点を**加える/締める**。全面書き換えはしない。

### S1. 誤検出を減らす
- **辞書の日本語キーは 2 書記素以上**でのみ部分一致させる (1 文字キーは `normalized.contains` で過剰一致しやすいので対象外)。Latin キーは現状どおり `tokens.contains`(語全体一致) を維持。
- **SF 検索 (第3層) を締める**: 現在 `tokens where token.count >= 3` で `catalog.contains` (完全一致) → `catalog.names(forTerm:)` (曖昧一致) を試す。曖昧一致 (`names(forTerm:)`) は誤爆源なので、**トークン長 4 以上 かつ stop-word でない**ときだけに限定する。完全一致 (`catalog.contains(token)`) は 3 以上のまま。
- **stop-word 集合**を追加 (提案として弱い一般語): 例 `new, old, my, the, and, for, temp, tmp, misc, other, data, file, files, folder, backup, download, downloads, work, test, project` と日本語 `その他, 新規, 一時, 資料` など。stop-word はキー一致・SF 検索の対象から除く (ただし辞書に明示キーとして入っている語はそのまま有効 — stop-word 除外は「規則的な曖昧一致」にのみ効かせ、辞書の明示一致には効かせない)。
- 数字のみ・記号のみのトークンは記号/絵文字候補にしない (現状の年・短コードは文字候補として維持)。

### S2. 並び順 (ランク) の改善
辞書一致に**「名前まるごと一致」層**を最上位で加える:
- 正規化フォルダ名そのもの、または名前の 1 トークンが、辞書キーと**完全一致**する項目を最優先 (キー長より優先)。
- 次に現状の「キー長の長い順、同長はフォルダ名で先に出た順」。
- 実装: `hits` に `isWholeMatch: Bool` を持たせ、ソートを `(isWholeMatch, key.count, -position)` の降順に変える。中身の種類 (第2の埋め) と代表画像は現状の位置 (空き枠のみ・末尾) を維持。

### S3. 中身の種類判定を強化
- `ContentScanner.classify` の対応表を増やす: **電子書籍** (`.epub`, `com.amazon.mobi8-ebook` 等) → 新 `.ebook`、**フォント** (`.font`) → 新 `.font`、**3D モデル** (`.usd`, `.sceneKitScene`, `public.3d-content`) → 新 `.model`、**字幕/プレーンテキストの細分は不要**。新 `ContentKind` には `dictionaryKey`・`reason`・辞書項目 (記号/絵文字) を用意する (例 ebook→`book.fill`/📚、font→`textformat`/🔤、model→`cube.fill`/🧊)。列挙順は「具体的な種類を先、汎用 (document) を後」を保つ。
- **代表画像の選び方**: 極端に小さい画像 (長辺 < 64px 目安、アイコン素材やサムネイル) を代表から除外し、残りから現状の基準 (新しい順) を維持。同点は大きい方。`ContentScanner` の代表選択にこのフィルタを足す。

### S4. 辞書の語彙を増やす + 他言語キー
- `suggestions.json` の各項目に **de/es/fr/ko/pt-BR/zh-Hant のキー**を追加 (今は日英中心)。既存の日英キーは残す。
- よく使うフォルダー名の項目を増やす (例: 請求書/領収書、契約、履歴書、旅行、レシピ、フォント、電子書籍、3D、ゲーム、フォント、壁紙 など) — 各項目に記号・絵文字と 8 言語キー。
- S3 で足した種類 (ebook/font/model) に対応する辞書項目も用意する (`kind.dictionaryKey` が引けるように)。

### テスト
- S1: 1 文字日本語キーが部分一致しない、Latin 語全体一致は効く、3 文字の曖昧 SF 検索は起きず 4 文字以上のみ、stop-word (例 "work") は曖昧一致しないが辞書に明示キーがあれば一致する。
- S2: 名前まるごと一致が長いキーの部分一致より先に来る (例: フォルダ「写真」で "写真" 完全一致が優先)。
- S3: 新種類 (ebook/font/model) が classify で当たる、代表画像で 64px 未満が除外される。
- S4: 追加した他言語キー (例 de "Rechnungen") でフォルダ名に一致する、`--check`/`build-xcstrings.py` は影響なし (suggestions.json は文言カタログではない)。

---

## T. ツール整備・Minor 残件 / Tooling & minor residuals

### T1. `--check` に指定子の型不一致検出
`build-xcstrings.py` の照合 (`--check` および `--stringsdata`) に、同じキーでコード側と `strings.json` 側の**書式指定子の並び/型が食い違う** (`%lld` vs `%@`、個数違い) 検出を足す。キーから指定子列を抽出 (`%%` は除外、`%lld`/`%@`/`%d` 等を順に) し、コード抽出キーと strings.json キーで指定子列が一致するか比べ、違えば `specifier mismatch: <key>` を出して exit 1。

### T2. FileWatcher の無駄な再読込を抑制
第5段階までの `FileWatcher` はユーザー辞書の**ディレクトリ**を監視するため、同じディレクトリの `history.json`/`presets.json` 保存でも `onChange` が発火し、`AppModel.reloadUserDictionary` が毎回走る (提案の再計算)。**辞書ファイルの内容ハッシュ (SHA-256) が前回と変わったときだけ**エンジンを作り直すようにする (mtime・サイズでの読み飛ばしはしない = spec §5.3 遵守、内容比較なので中身が同じ再保存や無関係ファイルの保存では作り直さない)。`AppModel` が「最後に読み込んだ辞書ファイルの内容ハッシュ」を持ち、reload 時に読み込んだ内容のハッシュと比べ、同じなら早期 return (提案は再計算しない)。壊れたファイルのアラート判定 (内容ごとに 1 回) は現状維持。

### T3. `check-compiled.sh` の引数エッジ / `IconComposer` の doc
- `check-compiled.sh`: `--stringsdata` に渡すディレクトリが空/不正なときのメッセージを明確化 (既に exit 2)。既知の軽微。
- `IconComposer` の doc コメントに、基準ピクセルが 512px であること (と複数解像度は各表現サイズで描くこと) を明記。

### テスト
- T1: 指定子不一致のキーを仕込むと `--check` が検出して exit 1、一致していれば従来どおり missing 0。
- T2: 辞書ファイルの内容が同じままディレクトリに無関係な書き込みが起きても、エンジンが作り直されない (提案が再計算されない) こと。内容が変わったら作り直されること。

---

## 全体の制約 / Global constraints (spec レベル)
- macOS 13.0 / Swift 5.9 (非 strict concurrency)。新規依存なし。
- 文言は `scripts/localization/strings.json`・`infoplist.json`・(新) `servicesmenu.json` から `build-xcstrings.py` で生成。8 言語。`--check` / `check-compiled.sh` missing 0。
- サンドボックス/entitlements 現状維持。main/develop 直コミット禁止 (作業ブランチ `feature/multires-i18n-suggestions`)。
- バージョン 1.7.0 / ビルド 10。README は関連箇所を日英併記で更新。

## 受け入れ条件 / Acceptance
1. V: アイコン適用が複数解像度になり、生成 NSImage が土台の表現サイズ集合を持つ。小サイズ表現がそのサイズで描かれている。リセット・既存合成テストは維持。
2. L: `ServicesMenu.xcstrings` を生成。実機で他言語メニュー名が追従するか検証し、通れば 8 言語化・通らなければ日本語据え置きで記録 (どちらでも可、結果を明記)。
3. S: S1〜S4 のルールが実装され、各ユニットテストが通る。誤検出が減り、まるごと一致が優先され、新種類が当たり、他言語キーが効く。
4. T: T1 の指定子不一致検出、T2 の内容ハッシュ再読込が実装・テストされる。
5. 全テスト成功、`--check`/`check-compiled.sh` missing 0、プロジェクト由来の警告 0。README・バージョン更新。
