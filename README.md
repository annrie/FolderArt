# FolderArt

<p align="center">
  <!-- License -->
  <a href="LICENSE">
    <img src="https://img.shields.io/github/license/annrie/FolderArt.svg" alt="License">
  </a>
  <!-- Latest release -->
  <a href="https://github.com/annrie/FolderArt/releases/latest">
    <img src="https://img.shields.io/github/v/release/annrie/FolderArt.svg" alt="Latest release">
  </a>
  <!-- Downloads total -->
  <a href="https://github.com/annrie/FolderArt/releases">
    <img src="https://img.shields.io/github/downloads/annrie/FolderArt/total.svg" alt="Total downloads">
  </a>
  <!-- Downloads latest release -->
  <a href="https://github.com/annrie/FolderArt/releases/latest">
    <img src="https://img.shields.io/github/downloads/annrie/FolderArt/latest/total.svg" alt="Latest release downloads">
  </a>
  <!-- Stars -->
  <a href="https://github.com/annrie/FolderArt/stargazers">
    <img src="https://img.shields.io/github/stars/annrie/FolderArt.svg" alt="Stars">
  </a>
</p>

macOS のフォルダーアイコンにカスタム画像を合成してアイコンを変更するアプリです。

## 機能 / Features

- 重ねるものを 4 種類から選択: 画像 / SF Symbols (制限付き記号は除外) / 絵文字 / 文字 — Overlay sources: image, SF Symbols (restricted symbols excluded), emoji, text
- 記号と文字の色を指定 — Tint color for symbols and text
- 文字のフォントと太さ: macOS 同梱の 8 種のフォントと 6 段階の太さ (太さは記号にも効く) — Font and weight for text: eight fonts bundled with macOS and six weights (weight also applies to symbols)
- お気に入り: 見た目 (オーバーレイ + 設定) を保存し 1 クリックで復元 — Presets: save a look and restore it in one click
- 複数フォルダへの一括適用、行を選べば一部だけに再適用 — Batch apply to many folders; select rows to re-apply to a subset
- フォルダ名と中身からの自動提案: 記号・絵文字・文字・お気に入りの候補をタブの上に最大 4 つ表示。直下のファイルの種類 (画像・動画・書類など) に合う記号・絵文字と、画像が多ければ代表画像 — Suggestions from the folder name and contents: up to four symbol / emoji / text / preset candidates above the tabs, plus a symbol / emoji for the dominant file kind and a representative image when images dominate。自分の辞書 (`suggestions-user.json`) で語を足せる — add your own words with a user dictionary
- お気に入りパック (`.folderartpack`): お気に入りを 1 ファイルで書き出し・読み込み、ダブルクリックで取り込み — Preset packs (`.folderartpack`): export and import all presets as one file; double-click to import。一部だけの書き出しも可 — partial export from the … menu
- プレビューに hover で拡大表示と 16/32/64/128px の実寸 — Hover the preview to enlarge it and see 16/32/64/128px renderings
- ドラッグ&ドロップ (複数フォルダ、ウィンドウ任意位置への画像) — Drag & drop (multiple folders, images anywhere in the window)
- 位置・サイズ・不透明度・上下位置・フォルダ形切り抜き — Position, size, opacity, vertical offset, clip to folder shape
- バックアップ、リセット、履歴 — Backup, reset, history
- 8 言語対応 (日本語・英語・ドイツ語・スペイン語・フランス語・韓国語・ポルトガル語 (ブラジル)・繁体字中国語) と「表示 > 言語」メニュー — Eight languages (Japanese, English, German, Spanish, French, Korean, Brazilian Portuguese, Traditional Chinese) and a View > Language menu
- Finder の右クリックからクイックアクション (FolderArt で開く / FolderArt で直前のお気に入りを適用 / FolderArt でアイコンを元に戻す) — Finder right-click Quick Actions (Open in FolderArt / Apply Last Preset in FolderArt / Reset Icon in FolderArt)

> **Note:** SF Symbols は macOS の実行時 API で描画しており、画像ファイルは同梱していません。Apple 製品や機能を表す制限付き記号は選択肢から除外しています。
> SF Symbols are rendered via macOS's runtime API, so no image files are bundled with the app. Restricted symbols that represent Apple products or features are excluded from the picker.

## スクリーンショット / Screenshots

<img width="760" alt="FolderArt 1.4.0" src="docs/images/main.png" />

## 動作環境 / Requirements

| 項目 / Item | 要件 / Requirement |
|------|------|
| OS | macOS 13 Ventura 以降 / macOS 13 Ventura or later |
| アーキテクチャ / Architecture | Apple Silicon / Intel |
| Xcode | 15 以上（ビルド時） / 15 or later (for building) |

## インストール / Installation

### ビルド済み .app を使う / Use the prebuilt .app

1. `FolderArt.app` をダウンロード / Download `FolderArt.app`
2. `/Applications` フォルダーへ移動 / Move it to the `/Applications` folder
3. 初回起動は **右クリック → 開く → 「開く」** で起動 / For the first launch, **right-click → Open → "Open"**

> **Note:** 現時点では Notarize 未対応のため、初回のみ右クリックからの起動が必要です。
> Notarization is not yet supported, so the right-click launch is needed only the first time.

### ソースからビルドする / Build from source

```bash
# 依存ツール
brew install xcodegen

# リポジトリを取得
git clone https://github.com/annrie/FolderArt.git
cd FolderArt

# プロジェクト生成
xcodegen generate

# ビルド（Debug）
xcodebuild build -scheme FolderArt -destination 'platform=macOS'

# テスト
xcodebuild test -scheme FolderArt -destination 'platform=macOS'
```

## 使い方 / Usage

1. **フォルダーをリストに追加** — 左のリストにフォルダーをドロップ（「＋」から複数選択も可）
   Add folders to the list: drop them on the left list, or pick several with the + button
2. **重ねるものを選ぶ** — 右の 4 タブから 画像 / 記号 / 絵文字 / 文字 を選択
   Choose what to overlay: the image, symbol, emoji, or text tab on the right
3. **設定を調整** — 配置・大きさ・不透明度・上下位置、記号と文字は色と太さ、文字はフォントも。
   **フォルダー形に切り抜く** を ON にすると、はみ出した部分をフォルダーの形で切り落とす
   Adjust position, size, opacity, vertical offset, tint and weight (symbols and text), and font (text).
   Turn on "clip to folder shape" to trim the overlay to the folder outline
   上下位置の既定は「下4%」(蓋つきのフォルダー本体の見た目の中心)
   The vertical position defaults to 4% down, the visual center of the folder body
4. **プレビューを確認** — 合成結果はその場で更新。プレビューに hover すると拡大表示と 16/32/64/128px の実寸が出る
   Check the preview: it updates as you go, and hovering enlarges it and shows 16/32/64/128px renderings
5. **適用** — 「N フォルダに適用」ボタン。リストで行を選んでいれば、その行だけに適用する
   Apply: the button applies to every folder in the list, or only to the rows you selected
6. **お気に入り** — 「＋」で今の見た目（重ねるもの + 設定）を保存し、チップをクリックで復元
   Presets: save the current look (overlay + settings) with +, and restore it by clicking its chip
   「…」の「選んで書き出す…」で一部だけをパックにできる
   Use "Export Selected…" in the … menu to pack only some presets
7. **元に戻す** — 「リセット」で適用先のアイコンを戻す。FolderArt が適用していないフォルダーには触らない
   Reset: restores the icons FolderArt applied; folders it never touched are left alone
8. **履歴** — ツールバーの「履歴」から、過去の適用を再適用したり、リセットしたりできる
   History: re-apply or reset a past application from the History sheet in the toolbar
9. **言語** — メニューバーの「表示 > 言語」から 8 言語を選べる (再起動で反映)
   Language: pick one of eight languages from View > Language in the menu bar (takes effect after a restart)

> **Note:** 欄の無い手書きのパックの上下位置は既定 (下4%) になります。
> A hand-written pack without a vertical position gets the default (4% down).

## 提案辞書のカスタマイズ / Customizing suggestions

「ファイル > 提案辞書を開く…」で `suggestions-user.json` (Application Support/FolderArt) を Finder に表示します。無ければ例を 1 件入れて作ります。形式は同梱の辞書と同じで、保存すると自動で反映されます (壊れていれば知らせます)。同じ語が同梱辞書にもあれば自分の辞書が優先されます。記号名は記号タブの検索で探せます。
File > Open Suggestion Dictionary… reveals `suggestions-user.json` (Application Support/FolderArt) in the Finder, creating it with one example if needed. It uses the bundled dictionary's format and is reloaded automatically when saved (you are told if it is broken). Your entries win over bundled ones for the same word. Symbol names can be found in the Symbol tab's search.

```json
[
  {"keys": ["案件", "project"], "symbol": "folder.fill.badge.gearshape", "emoji": "🗂️"},
  {"keys": ["請求書"], "emoji": "🧾"}
]
```

## クイックアクション / Quick Actions

Finder でフォルダーを右クリックすると、次の 3 つがサービスメニューに追加されます。
Right-click a folder in the Finder to find these three items in the services menu.

- **FolderArt で開く** — 選んだフォルダーを FolderArt のリストに追加し、アプリを前面化する
  Open in FolderArt: adds the selected folders to FolderArt's list and brings the app forward
- **FolderArt で直前のお気に入りを適用** — FolderArt を開かずに、直前に使ったお気に入りをそのまま適用する
  Apply Last Preset in FolderArt: applies the preset you used most recently, without opening FolderArt
- **FolderArt でアイコンを元に戻す** — FolderArt が付けたアイコンだけを、開かずに元に戻す
  Reset Icon in FolderArt: resets icons FolderArt applied, without opening FolderArt

3 つとも表示名が「FolderArt で〜」で始まるのは、右クリックのクイックアクション欄はアプリ別にまとまらず平坦に並ぶため、どのアプリの機能かひと目で分かるようにするためです。
All three names start with "… in FolderArt" because the right-click Quick Actions list is flat (not grouped by app), so the name alone shows which app a given action belongs to.

「FolderArt で直前のお気に入りを適用」と「FolderArt でアイコンを元に戻す」は静かに実行され、Finder 上でアイコンが変わることが完了の合図です (エラー時のみ FolderArt が前面に出てメッセージを出します)。「FolderArt で開く」は常にアプリを前面化します。
"Apply Last Preset in FolderArt" and "Reset Icon in FolderArt" run silently — the changed folder icon in the Finder is the confirmation (FolderArt only comes forward to show a message if something fails). "Open in FolderArt" always brings the app forward.

項目が出ない場合は、`FolderArt.app` を `/Applications` か `~/アプリケーション` に置いて一度起動してから、**システム設定 > キーボード > キーボードショートカット > サービス** で有効になっているか確認してください。
If the items don't appear, put `FolderArt.app` in `/Applications` or `~/Applications` and launch it once, then check that they're enabled under **System Settings > Keyboard > Keyboard Shortcuts > Services**.

## プロジェクト構成 / Project structure

```
FolderArt/
├── AppDelegate.swift           # 共有 AppModel の所有と NSServices の登録、静かな終了の判定
├── AppModel.swift              # 画面全体の状態を束ねる
├── ContentView.swift           # メイン画面の組み立て
├── FolderArtApp.swift          # アプリのエントリポイント
├── Models/
│   ├── CodableColor.swift      # JSON に保存できる sRGB 色・フォント太さ
│   ├── CompositionSettings.swift # 合成設定（配置・大きさ・色・フォントなど）
│   ├── IconTask.swift          # 履歴 1 行（v1 からの移行を含む）
│   ├── Overlay.swift           # 重ねるもの（画像 / 記号 / 絵文字 / 文字）
│   ├── Pack.swift              # お気に入りパックの形式
│   ├── Preset.swift            # お気に入り（重ねるもの + 設定）
│   ├── PresetExportSelection.swift # 「選んで書き出す」の選択状態
│   └── Suggestion.swift        # 提案 1 つ（記号 / 絵文字 / 文字 / お気に入り / 代表画像）
├── Services/
│   ├── AppLanguage.swift       # 言語メニューの選択と AppleLanguages への保存
│   ├── ApplyCoordinator.swift  # 複数フォルダへの一括適用とリセット
│   ├── BitmapCanvas.swift      # sRGB ビットマップへの描画ヘルパ
│   ├── BookmarkManager.swift   # Security-Scoped Bookmark 管理
│   ├── ContentScanner.swift    # フォルダ直下の種類と代表画像
│   ├── FileIdentity.swift      # フォルダの同一性（ボリューム UUID + inode）
│   ├── FileWatcher.swift       # ユーザー辞書の監視 (ディレクトリ + ファイル)
│   ├── FolderIconManager.swift # NSWorkspace アイコン操作・バックアップ
│   ├── FontCatalog.swift       # 厳選フォントと家族 + 太さの解決
│   ├── IconComposer.swift      # 標準フォルダーアイコンとの合成
│   ├── MaintenanceSweep.swift  # 起動時の掃除（未参照のバックアップ・隔離ファイル）
│   ├── OverlayRenderer.swift   # 4 種類を正方形画像に描画
│   ├── PackReader.swift        # パックの読み込みと検証
│   ├── PackWriter.swift        # パックの書き出し
│   ├── PresetImporter.swift    # パックからお気に入りへの取り込み
│   ├── QuickActionProvider.swift # NSServices の提供オブジェクト (pboard → AppModel への薄い委譲)
│   ├── SuggestionDictionary.swift # 提案辞書（suggestions.json + suggestions-user.json）の読み込み
│   ├── SuggestionEngine.swift  # フォルダ名と中身からの提案
│   └── SymbolCatalog.swift     # SF Symbols のカタログ（制限付きは除外）
├── State/
│   ├── FolderSelection.swift   # 適用先フォルダのリストと選択
│   └── OverlayState.swift      # 重ねるものと設定・プレビュー
├── Stores/
│   ├── AssetStore.swift        # 画像を 512px PNG で複製・回収
│   ├── CodableStore.swift      # JSON の読み書き・破損ファイルの退避
│   ├── HistoryStore.swift      # 適用履歴
│   ├── LastPresetStore.swift   # 直前に使ったお気に入りの id を永続化
│   └── PresetStore.swift       # お気に入り
├── Views/
│   ├── ControlsView.swift      # 設定スライダーと色
│   ├── DropZoneView.swift      # D&D ゾーン（AppKit 実装）
│   ├── FolderListView.swift    # 適用先フォルダのリスト
│   ├── HistoryView.swift       # 履歴シート
│   ├── OverlayPickerView.swift # 4 タブの選択画面
│   ├── PresetExportPickerView.swift # 「選んで書き出す」の popover
│   ├── PresetStripView.swift   # お気に入りのチップ列
│   ├── PreviewView.swift       # プレビューと hover 拡大
│   ├── SuggestionStripView.swift # 提案のチップ列
│   └── SymbolGridView.swift    # 記号の検索とグリッド
└── Resources/
    ├── InfoPlist.xcstrings     # 書類の種類名 (8 言語、生成物)
    ├── Localizable.xcstrings   # UI の文言 (8 言語、生成物)
    ├── restricted-symbols.txt  # 制限付き記号の同梱 fallback
    └── suggestions.json        # 提案辞書（語 → 記号・絵文字）
scripts/localization/
├── strings.json                # 文言の元 (キー → 8 言語)
├── infoplist.json              # InfoPlist 用の文言
├── build-xcstrings.py          # .xcstrings の生成と、ソースとの突き合わせ (--check / --stringsdata)
└── check-compiled.sh           # コンパイラ抽出のキーとの厳密照合
```

## 技術詳細 / Technical details

- **Swift 5.9 + SwiftUI + AppKit**（macOS 13+）— Swift 5.9 + SwiftUI + AppKit (macOS 13+)
- **App Sandbox** 対応（Security-Scoped Bookmark でフォルダーアクセスを永続化）— **App Sandbox** support, persisting folder access with Security-Scoped Bookmarks
- **Core Graphics / NSBitmapImageRep** による高品質な画像合成 — High-quality image compositing with **Core Graphics / NSBitmapImageRep**
- `NSCompositingOperation.destinationIn` でフォルダー形状クリッピング — Folder-shape clipping via `NSCompositingOperation.destinationIn`
- AppKit `NSDraggingDestination` による信頼性の高いドラッグ＆ドロップ — Reliable drag & drop with AppKit's `NSDraggingDestination`
- **String Catalog** による 8 言語対応 (`scripts/localization/strings.json` から生成) — Eight-language support via **String Catalog**, generated from `scripts/localization/strings.json`

## ライセンス / License

MIT License

## 作者 / Author

[@annrie](https://github.com/annrie)
