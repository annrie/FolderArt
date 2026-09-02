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

1. **フォルダーを選択** — 左のドロップゾーンにフォルダーをドロップ（またはボタンから選択）
2. **画像を選択** — 右のドロップゾーンに画像をドロップ（PNG / JPEG / HEIC / GIF / WebP 対応）
3. **設定を調整**
   - **フルイメージ** チェック ON: 画像がフォルダー形状に自動フィット（推奨）
   - チェック OFF: スケール・不透明度・上下位置を手動調整
4. **プレビューを確認** — 合成結果をリアルタイムで確認
5. **アイコンを適用** — 「アイコンを適用」ボタンをクリック
6. **リセット** — 元に戻したい場合はフォルダーを選択して「リセット」ボタン

## プロジェクト構成

```
FolderArt/
├── Models/
│   └── IconTask.swift          # タスクモデル・配置列挙型
├── Services/
│   ├── BookmarkManager.swift   # Security-Scoped Bookmark 管理
│   ├── FolderIconManager.swift # NSWorkspace アイコン操作
│   └── IconComposer.swift      # Core Graphics 画像合成
├── Stores/
│   └── HistoryStore.swift      # JSON 永続化履歴管理
├── Views/
│   ├── ContentView.swift       # メイン画面
│   ├── ControlsView.swift      # 設定スライダー
│   ├── DropZoneView.swift      # D&D ゾーン（AppKit 実装）
│   └── HistoryView.swift       # 履歴シート
└── ContentViewModel.swift      # メイン ViewModel
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
