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

## 機能

- 重ねるものを 4 種類から選択: 画像 / SF Symbols (制限付き記号は除外) / 絵文字 / 文字 — Overlay sources: image, SF Symbols (restricted symbols excluded), emoji, text
- 記号と文字の色を指定 — Tint color for symbols and text
- お気に入り: 見た目 (オーバーレイ + 設定) を保存し 1 クリックで復元 — Presets: save a look and restore it in one click
- 複数フォルダへの一括適用、行を選べば一部だけに再適用 — Batch apply to many folders; select rows to re-apply to a subset
- プレビューに hover で拡大表示と 16/32/64/128px の実寸 — Hover the preview to enlarge it and see 16/32/64/128px renderings
- ドラッグ&ドロップ (複数フォルダ、ウィンドウ任意位置への画像) — Drag & drop (multiple folders, images anywhere in the window)
- 位置・サイズ・不透明度・上下位置・フォルダ形切り抜き — Position, size, opacity, vertical offset, clip to folder shape
- バックアップ、リセット、履歴 — Backup, reset, history

> **Note:** SF Symbols は macOS の実行時 API で描画しており、画像ファイルは同梱していません。Apple 製品や機能を表す制限付き記号は選択肢から除外しています。
> SF Symbols are rendered via macOS's runtime API, so no image files are bundled with the app. Restricted symbols that represent Apple products or features are excluded from the picker.

## スクリーンショット

<img width="712" height="819" alt="Image" src="https://github.com/user-attachments/assets/9b2ec7b7-9839-46d6-8b8c-5e8a6306b166" />

## 動作環境

| 項目 | 要件 |
|------|------|
| OS | macOS 13 Ventura 以降 |
| アーキテクチャ | Apple Silicon / Intel |
| Xcode | 15 以上（ビルド時） |

## インストール

### ビルド済み .app を使う

1. `FolderArt.app` をダウンロード
2. `/Applications` フォルダーへ移動
3. 初回起動は **右クリック → 開く → 「開く」** で起動

> **Note:** 現時点では Notarize 未対応のため、初回のみ右クリックからの起動が必要です。

### ソースからビルドする

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

## 使い方

1. **フォルダーをリストに追加** — 左のリストにフォルダーをドロップ（「＋」から複数選択も可）
   Add folders to the list: drop them on the left list, or pick several with the + button
2. **重ねるものを選ぶ** — 右の 4 タブから 画像 / 記号 / 絵文字 / 文字 を選択
   Choose what to overlay: the image, symbol, emoji, or text tab on the right
3. **設定を調整** — 配置・大きさ・不透明度・上下位置、記号と文字は色も。
   **フォルダー形に切り抜く** を ON にすると、はみ出した部分をフォルダーの形で切り落とす
   Adjust position, size, opacity, vertical offset, and (for symbols and text) tint.
   Turn on "clip to folder shape" to trim the overlay to the folder outline
4. **プレビューを確認** — 合成結果はその場で更新。プレビューに hover すると拡大表示と 16/32/64/128px の実寸が出る
   Check the preview: it updates as you go, and hovering enlarges it and shows 16/32/64/128px renderings
5. **適用** — 「N フォルダに適用」ボタン。リストで行を選んでいれば、その行だけに適用する
   Apply: the button applies to every folder in the list, or only to the rows you selected
6. **お気に入り** — 「＋」で今の見た目（重ねるもの + 設定）を保存し、チップをクリックで復元
   Presets: save the current look (overlay + settings) with +, and restore it by clicking its chip
7. **元に戻す** — 「リセット」で適用先のアイコンを戻す。FolderArt が適用していないフォルダーには触らない
   Reset: restores the icons FolderArt applied; folders it never touched are left alone
8. **履歴** — ツールバーの「履歴」から、過去の適用を再適用したり、リセットしたりできる
   History: re-apply or reset a past application from the History sheet in the toolbar

## プロジェクト構成

```
FolderArt/
├── AppModel.swift              # 画面全体の状態を束ねる
├── ContentView.swift           # メイン画面の組み立て
├── FolderArtApp.swift          # アプリのエントリポイント
├── Models/
│   ├── CodableColor.swift      # JSON に保存できる sRGB 色・フォント太さ
│   ├── CompositionSettings.swift # 合成設定（配置・大きさ・色など）
│   ├── IconTask.swift          # 履歴 1 行（v1 からの移行を含む）
│   ├── Overlay.swift           # 重ねるもの（画像 / 記号 / 絵文字 / 文字）
│   └── Preset.swift            # お気に入り（重ねるもの + 設定）
├── Services/
│   ├── ApplyCoordinator.swift  # 複数フォルダへの一括適用とリセット
│   ├── BitmapCanvas.swift      # sRGB ビットマップへの描画ヘルパ
│   ├── BookmarkManager.swift   # Security-Scoped Bookmark 管理
│   ├── FolderIconManager.swift # NSWorkspace アイコン操作・バックアップ
│   ├── IconComposer.swift      # 標準フォルダーアイコンとの合成
│   ├── OverlayRenderer.swift   # 4 種類を正方形画像に描画
│   └── SymbolCatalog.swift     # SF Symbols のカタログ（制限付きは除外）
├── State/
│   ├── FolderSelection.swift   # 適用先フォルダのリストと選択
│   └── OverlayState.swift      # 重ねるものと設定・プレビュー
├── Stores/
│   ├── AssetStore.swift        # 画像を 512px PNG で複製・回収
│   ├── CodableStore.swift      # JSON の読み書き・破損ファイルの退避
│   ├── HistoryStore.swift      # 適用履歴
│   └── PresetStore.swift       # お気に入り
├── Views/
│   ├── ControlsView.swift      # 設定スライダーと色
│   ├── DropZoneView.swift      # D&D ゾーン（AppKit 実装）
│   ├── FolderListView.swift    # 適用先フォルダのリスト
│   ├── HistoryView.swift       # 履歴シート
│   ├── OverlayPickerView.swift # 4 タブの選択画面
│   ├── PresetStripView.swift   # お気に入りのチップ列
│   ├── PreviewView.swift       # プレビューと hover 拡大
│   └── SymbolGridView.swift    # 記号の検索とグリッド
└── Resources/
    └── restricted-symbols.txt  # 制限付き記号の同梱 fallback
```

## 技術詳細

- **Swift 5.9 + SwiftUI + AppKit**（macOS 13+）
- **App Sandbox** 対応（Security-Scoped Bookmark でフォルダーアクセスを永続化）
- **Core Graphics / NSBitmapImageRep** による高品質な画像合成
- `NSCompositingOperation.destinationIn` でフォルダー形状クリッピング
- AppKit `NSDraggingDestination` による信頼性の高いドラッグ＆ドロップ

## ライセンス

MIT License

## 作者

[@annrie](https://github.com/annrie)
