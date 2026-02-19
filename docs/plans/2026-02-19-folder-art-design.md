# FolderArt — 設計ドキュメント

**作成日**: 2026-02-19
**バージョン**: 1.0
**ステータス**: 承認済み

---

## 概要

macOS 上でフォルダーアイコンに任意の画像をオーバーレイ合成できるシングルウィンドウアプリ。フォルダーアイコンの形状を残しつつ、その上にカスタム画像を貼り付けることで、Finder 上での視認性を保ちながら個性的なフォルダーアイコンを作成できる。

---

## 要件

### 機能要件

- フォルダーの指定: ドラッグ＆ドロップ および ファイル選択ダイアログ
- カスタム画像の指定: ドラッグ＆ドロップ および ファイル選択ダイアログ
- 画像の配置位置: 中央オーバーレイ または 右下バッジ（ユーザーが選択）
- 画像サイズ: スライダーで 20〜100% 調整
- 画像不透明度: スライダーで 10〜100% 調整
- ライブプレビュー: パラメーター変更のたびにリアルタイム更新
- アイコン適用: NSWorkspace.setIcon でアイコンを Finder に反映
- リセット機能: 変更前のアイコンをバックアップし、元に戻せる
- 変更履歴: 過去に適用したアイコン変更の一覧表示と個別リセット

### 非機能要件

- 対応 macOS: macOS 13 Ventura 以降
- 言語: Swift 5.9 以降
- UI フレームワーク: SwiftUI
- App Store 配布対応（App Sandbox 必須）
- 対応画像フォーマット: PNG, JPEG, HEIC, GIF, WebP

---

## アーキテクチャ

### プロジェクト構成

```
FolderArt/
├── FolderArtApp.swift         # アプリエントリーポイント
├── ContentView.swift          # メインUI（SwiftUI）
├── Views/
│   ├── DropZoneView.swift     # ドロップゾーンコンポーネント
│   ├── PreviewView.swift      # アイコンプレビュー
│   ├── ControlsView.swift     # スライダー・ラジオボタン等
│   └── HistoryView.swift      # 変更履歴シート
├── Services/
│   ├── IconComposer.swift     # Core Graphics による画像合成
│   ├── FolderIconManager.swift # NSWorkspace アイコン変更
│   └── BookmarkManager.swift  # Security-Scoped Bookmarks 管理
├── Stores/
│   └── HistoryStore.swift     # 変更履歴の永続化（JSON）
└── Models/
    └── IconTask.swift         # 変更タスクのデータモデル
```

### データフロー

```
ユーザー操作
    │
    ├── フォルダーを指定（D&D or NSOpenPanel）
    │       └── BookmarkManager で Security-Scoped Bookmark 保存
    │
    ├── 画像を指定（D&D or NSOpenPanel）
    │
    ├── 配置・サイズ・不透明度を調整
    │       └── IconComposer がリアルタイムでプレビュー生成
    │
    └── 「適用」ボタン
            ├── FolderIconManager: 元アイコンをバックアップ保存
            ├── IconComposer: 最終合成画像を生成
            ├── NSWorkspace.setIcon でアイコン書き込み
            └── HistoryStore に変更を記録
```

---

## UIレイアウト

```
┌─────────────────────────────────────────────────────┐
│  FolderArt                            [履歴] [?]     │
├────────────────────────┬────────────────────────────┤
│                        │                            │
│  📁 フォルダーを        │  🖼 カスタム画像を          │
│     ここにドロップ      │     ここにドロップ          │
│  [または選択...]       │  [または選択...]            │
│                        │                            │
│  /Users/.../Desktop/   │  photo.png                 │
│  Documents             │  (512×512 PNG)             │
│                        │                            │
├────────────────────────┴────────────────────────────┤
│  画像の配置:  ○ 中央オーバーレイ  ○ 右下バッジ        │
│  サイズ:     [────●────────] 60%                    │
│  不透明度:   [─────────●──] 90%                     │
├─────────────────────────────────────────────────────┤
│              【 プレビュー 】                         │
│                                                     │
│           [フォルダーアイコン+画像の合成]              │
│                ※ 実際のサイズで表示                  │
│                                                     │
├─────────────────────────────────────────────────────┤
│     [🔄 リセット]            [✅ アイコンを適用]      │
└─────────────────────────────────────────────────────┘
```

---

## 技術詳細

### 画像合成（IconComposer）

1. `NSWorkspace.shared.icon(forFile:)` で現在のフォルダーアイコン取得
2. システムフォルダーアイコンを 512×512 にリサイズ
3. ユーザー画像をリサイズ（設定サイズ%）し、不透明度を適用
4. 位置計算:
   - **中央オーバーレイ**: フォルダーアイコンの中心に配置
   - **右下バッジ**: フォルダーアイコンの右下 1/4 エリアに配置
5. `CGContext` でレイヤー合成 → `NSImage` に変換
6. `NSWorkspace.shared.setIcon(_:forFile:options:)` でアイコン書き込み

### App Sandbox 対応

- **Entitlement**: `com.apple.security.files.user-selected.read-write`
- ユーザーが `NSOpenPanel` または D&D で指定したファイル・フォルダーへのアクセス権限を自動取得
- **Security-Scoped Bookmarks** でフォルダーパスを `UserDefaults` に保存し、次回起動時にもアクセス継続

### バックアップ・履歴

- バックアップ保存先: `~/Library/Application Support/FolderArt/backups/<hash>/original.icns`
- 履歴データ: `~/Library/Application Support/FolderArt/history.json`
- `IconTask` モデル:
  ```swift
  struct IconTask: Codable {
      let id: UUID
      let folderPath: String        // Security-Scoped Bookmark
      let appliedAt: Date
      let backupPath: String
      let imageName: String
      let position: IconPosition    // .center | .badge
      let scale: Double
      let opacity: Double
  }
  ```

---

## エラーハンドリング

| ケース | 対応 |
|--------|------|
| 書き込み権限なし | アラートダイアログで通知、権限取得方法を案内 |
| 対応外の画像フォーマット | エラーメッセージ表示（PNG/JPEG/HEIC/GIF/WebP 以外） |
| フォルダーが存在しない | 無効なブックマークをクリア、ユーザーに通知 |
| 画像サイズが大きすぎる | 自動的に 1024px 以下にリサイズして処理継続 |
| アイコン設定失敗 | エラー詳細をアラートで表示、バックアップは保持 |

---

## テスト方針

### ユニットテスト
- `IconComposer`: 各配置モード（中央/右下）の合成ロジック
- `BookmarkManager`: Bookmark の保存・読み込み・無効化検知
- `HistoryStore`: 履歴の追加・削除・永続化

### UIテスト（XCUITest）
- ドロップゾーンへのファイルドロップ
- スライダー操作とプレビュー更新
- 「適用」ボタンでアイコンが変更されること
- 「リセット」ボタンで元のアイコンに戻ること

---

## 将来的な拡張（YAGNI により現時点では実装しない）

- 複数フォルダーへの一括適用
- アイコンプリセットのライブラリ
- Finder コンテキストメニュー拡張
