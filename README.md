# FolderArt

macOS のフォルダーアイコンにカスタム画像を合成してアイコンを変更するアプリです。

## 機能

- **ドラッグ＆ドロップ** — Finder からフォルダーや画像をドロップして選択
- **フルイメージモード** — 画像をフォルダー形状に自動フィット＆クリップ（デフォルト）
- **手動サイズ調整** — スケール・不透明度・上下位置をスライダーで調整
- **配置モード** — 中央オーバーレイ / 右下バッジの2種類
- **プレビュー** — 適用前にリアルタイムで合成結果を確認
- **バックアップ＆リセット** — 元のアイコンを自動バックアップ、ワンクリックで復元
- **履歴管理** — 適用済みフォルダーの一覧と個別リセット

## スクリーンショット

<img width="746" height="819" alt="Image" src="https://github.com/user-attachments/assets/cbfb4c9b-ceff-47be-b3e7-370225a0f85d" />

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
