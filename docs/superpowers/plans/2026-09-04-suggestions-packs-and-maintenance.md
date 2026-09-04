# FolderArt 第2段階 実装計画: 自動提案・お気に入りパック・内部改善

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フォルダ名から記号・絵文字・文字・お気に入りを提案し、お気に入りを `.folderartpack` で配布でき、履歴の同一性・書き込み回数・掃除の持ち越しを片付けた FolderArt 1.3.0 を作る。

**Architecture:** 提案は純関数 `SuggestionEngine` (同梱辞書 + `SymbolCatalog` の検索語 + 規則) が `[Suggestion]` を返し、`AppModel` がフォルダ選択の変化に合わせて再計算して `SuggestionStripView` に流す。パックは `PackWriter` / `PackReader` / `PresetImporter` の 3 部品で、`PresetStore.addAll` により 1 回の保存で取り込む。履歴は `fileID` (ボリューム UUID + inode 番号) で同一性を判定し、一括適用は `HistoryStore.upsertAll` で最後に 1 回だけ保存する。

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 13.0+, XcodeGen (project.yml が正), XCTest。

**Spec:** `docs/superpowers/specs/2026-09-03-suggestions-packs-and-maintenance-design.md`

## Global Constraints

- deploymentTarget macOS 13.0、SWIFT_VERSION 5.9。macOS 14 以降専用 API は使わない (`@Observable` 不可、`onChange(of:initial:)` 不可、`onChange(of:) { value in }` の 1 引数形を使う)。
- 新しいファイルを追加したら `xcodegen generate` を実行し、`FolderArt.xcodeproj/project.pbxproj` の差分もコミットに含める。`FolderArt/Resources/*.json` / `*.txt` は XcodeGen が自動でリソースに入れる。
- テスト実行コマンド (以後「テスト実行」):
  ```bash
  xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"
  ```
  1 クラスだけ走らせるときは `-only-testing:FolderArtTests/<ClassName>` を足す。プロジェクト由来の `warning:` は 0 件を保つ (XCTest の `ld: warning` 2 本は環境由来で無視)。
- テストはアプリ自身をホストとしてサンドボックス内で走る (`BookmarkManager.isSandboxed == true`)。一時ファイルは `FileManager.default.temporaryDirectory` 配下に作れば読み書きできる。
- 新しい UI 文言は `Text("…")` (自動で `LocalizedStringKey`) か `String(localized:)`。`String` 連結で作った文言を `Text` に渡さない。
- 新しい依存パッケージは追加しない。SF Symbols の画像を同梱しない。
- コミットメッセージは既存の流儀 (`feat: ✨ …`, `fix: 🐛 …`, `refactor: ♻️ …`, `test: ✅ …`, `docs: 📝 …`, `chore: 🔧 …` + 日本語) に合わせ、末尾に次を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FJnasAEYf6hgjPTNwdy9EK
  ```
- ブランチは `feature/suggestions-packs` (作成済み、`develop` = `main` = v1.2.1 から分岐)。main / develop には直接コミットしない。
- 既存の 107 テストは維持する。

## File Structure

```
FolderArt/
├── AppModel.swift                     変更: suggestions / applySuggestion / exportPack / importPack / 起動時の掃除
├── FolderArtApp.swift                 変更: ファイルメニュー (通知で ContentView に依頼)
├── ContentView.swift                  変更: onOpenURL、メニュー通知の受け口、SuggestionStripView / PresetStripView の配線
├── Models/
│   ├── IconTask.swift                 変更: fileID: String?
│   ├── Suggestion.swift               新規: Suggestion 値型
│   └── Pack.swift                     新規: Pack / PackEntry / PackError / ImportSummary
├── Services/
│   ├── SuggestionDictionary.swift     新規: suggestions.json の読み込み
│   ├── SuggestionEngine.swift         新規: 提案の計算 (純関数)
│   ├── FileIdentity.swift             新規: ボリューム UUID + ファイル ID の文字列化
│   ├── PackWriter.swift               新規
│   ├── PackReader.swift               新規 (検証込み)
│   ├── PresetImporter.swift           新規
│   ├── MaintenanceSweep.swift         新規
│   ├── ApplyCoordinator.swift         変更: fileID の記録、最後に 1 回保存、最終保存失敗で一括巻き戻し
│   ├── FolderIconManager.swift        変更: removeBackup(atBackupPath:)
│   └── SymbolCatalog.swift            変更: names(forTerm:) (検索語の逆引き)
├── Stores/
│   ├── HistoryStore.swift             変更: fileID による置き換え、task(forFolderPath:fileID:)、upsertAll、saveCount
│   └── PresetStore.swift              変更: addAll
├── Views/
│   ├── SuggestionStripView.swift      新規
│   ├── OverlayPickerView.swift        変更: 上に提案の帯
│   └── PresetStripView.swift          変更: 「…」メニュー
└── Resources/
    └── suggestions.json               新規
FolderArtTests/
├── SuggestionDictionaryTests.swift    新規
├── SuggestionEngineTests.swift        新規
├── PackTests.swift                    新規 (Writer/Reader)
├── PresetImporterTests.swift          新規
├── FileIdentityTests.swift            新規
├── HistoryStoreTests.swift            変更: fileID、upsertAll
├── ApplyCoordinatorTests.swift        変更: 1 回保存、最終保存失敗の一括巻き戻し
├── MaintenanceSweepTests.swift        新規
├── AppModelTests.swift                変更: 提案の導出、パックの読み込み
└── PresetStoreTests.swift             変更: addAll
```

---

### Task 1: 提案辞書 (SuggestionDictionary + suggestions.json)

**Files:**
- Create: `FolderArt/Services/SuggestionDictionary.swift`
- Create: `FolderArt/Resources/suggestions.json`
- Test: `FolderArtTests/SuggestionDictionaryTests.swift`

**Interfaces:**
- Produces:
  - `struct SuggestionEntry: Codable, Equatable, Sendable { let keys: [String]; let symbol: String?; let emoji: String? }`
  - `struct SuggestionDictionary: Equatable { let entries: [SuggestionEntry]; static let empty; static func load(bundle: Bundle = .main) -> SuggestionDictionary; init(entries:) }`
  - `SuggestionDictionary.load` は読めなければ `.empty` (提案は規則と検索語だけで動く)。

- [ ] **Step 1: 辞書ファイルを作る**

`FolderArt/Resources/suggestions.json` (日本語キーは 2 文字以上、記号名は制限付きでないもの。全部で 100 語):

```json
[
  {"keys": ["写真", "フォト", "photo", "photos", "picture", "pictures", "pics", "camera"], "symbol": "photo.fill", "emoji": "📷"},
  {"keys": ["画像", "イメージ", "image", "images", "img", "graphics"], "symbol": "photo.on.rectangle", "emoji": "🖼️"},
  {"keys": ["動画", "ビデオ", "映像", "video", "videos", "movie", "movies", "film"], "symbol": "film.fill", "emoji": "🎬"},
  {"keys": ["音楽", "ミュージック", "music", "songs", "audio", "mp3"], "symbol": "music.note", "emoji": "🎵"},
  {"keys": ["書類", "ドキュメント", "文書", "document", "documents", "docs", "doc"], "symbol": "doc.text.fill", "emoji": "📄"},
  {"keys": ["請求", "請求書", "invoice", "invoices", "billing"], "symbol": "doc.text.fill", "emoji": "🧾"},
  {"keys": ["領収", "領収書", "レシート", "receipt", "receipts"], "symbol": "doc.plaintext.fill", "emoji": "🧾"},
  {"keys": ["見積", "見積書", "estimate", "estimates", "quote", "quotes"], "symbol": "doc.badge.ellipsis", "emoji": "📝"},
  {"keys": ["契約", "契約書", "contract", "contracts", "agreement"], "symbol": "doc.text.fill", "emoji": "📜"},
  {"keys": ["会計", "経理", "帳簿", "accounting", "finance", "finances", "ledger"], "symbol": "chart.bar.doc.horizontal.fill", "emoji": "💹"},
  {"keys": ["税金", "税務", "確定申告", "tax", "taxes"], "symbol": "percent", "emoji": "🧮"},
  {"keys": ["銀行", "口座", "bank", "banking"], "symbol": "building.columns.fill", "emoji": "🏦"},
  {"keys": ["給与", "給料", "payroll", "salary"], "symbol": "yensign.circle.fill", "emoji": "💴"},
  {"keys": ["予算", "budget", "budgets"], "symbol": "chart.pie.fill", "emoji": "📊"},
  {"keys": ["仕事", "業務", "work", "job", "office"], "symbol": "briefcase.fill", "emoji": "💼"},
  {"keys": ["案件", "プロジェクト", "project", "projects"], "symbol": "folder.fill.badge.gearshape", "emoji": "🗂️"},
  {"keys": ["顧客", "クライアント", "取引先", "client", "clients", "customer", "customers"], "symbol": "person.2.fill", "emoji": "🤝"},
  {"keys": ["会議", "打合せ", "ミーティング", "meeting", "meetings"], "symbol": "person.3.fill", "emoji": "🗣️"},
  {"keys": ["資料", "material", "materials", "reference", "references"], "symbol": "books.vertical.fill", "emoji": "📚"},
  {"keys": ["報告", "報告書", "レポート", "report", "reports"], "symbol": "doc.richtext.fill", "emoji": "📑"},
  {"keys": ["企画", "提案", "提案書", "proposal", "proposals", "plan", "plans", "planning"], "symbol": "lightbulb.fill", "emoji": "💡"},
  {"keys": ["設計", "仕様", "仕様書", "design", "designs", "spec", "specs"], "symbol": "pencil.and.ruler.fill", "emoji": "📐"},
  {"keys": ["開発", "コード", "ソース", "develop", "development", "dev", "code", "source", "src", "repo", "repos", "git", "github"], "symbol": "chevron.left.forwardslash.chevron.right", "emoji": "💻"},
  {"keys": ["アプリ", "app", "apps", "application", "applications"], "symbol": "app.fill", "emoji": "📱"},
  {"keys": ["ウェブ", "サイト", "web", "website", "websites", "site", "html"], "symbol": "globe", "emoji": "🌐"},
  {"keys": ["データ", "data", "dataset", "datasets", "database", "db", "sql"], "symbol": "cylinder.split.1x2.fill", "emoji": "🗄️"},
  {"keys": ["バックアップ", "backup", "backups", "archive", "archives"], "symbol": "archivebox.fill", "emoji": "🗃️"},
  {"keys": ["ダウンロード", "download", "downloads", "dl"], "symbol": "arrow.down.circle.fill", "emoji": "⬇️"},
  {"keys": ["アップロード", "upload", "uploads"], "symbol": "arrow.up.circle.fill", "emoji": "⬆️"},
  {"keys": ["デスクトップ", "desktop"], "symbol": "desktopcomputer", "emoji": "🖥️"},
  {"keys": ["デザイン", "図案", "artwork", "art", "illustration", "illustrations", "graphic"], "symbol": "paintpalette.fill", "emoji": "🎨"},
  {"keys": ["ロゴ", "logo", "logos", "brand", "branding"], "symbol": "seal.fill", "emoji": "🏷️"},
  {"keys": ["フォント", "font", "fonts", "typography"], "symbol": "textformat", "emoji": "🔤"},
  {"keys": ["アイコン", "icon", "icons"], "symbol": "app.badge.fill", "emoji": "🔘"},
  {"keys": ["スクリーンショット", "screenshot", "screenshots", "screen"], "symbol": "camera.viewfinder", "emoji": "📸"},
  {"keys": ["本", "書籍", "読書", "book", "books", "reading", "library", "ebook", "ebooks"], "symbol": "book.fill", "emoji": "📖"},
  {"keys": ["論文", "研究", "paper", "papers", "research", "thesis", "academic"], "symbol": "graduationcap.fill", "emoji": "🎓"},
  {"keys": ["学校", "授業", "学習", "勉強", "school", "class", "classes", "study", "lecture", "lectures", "course", "courses"], "symbol": "graduationcap.fill", "emoji": "🏫"},
  {"keys": ["メモ", "ノート", "note", "notes", "memo", "memos"], "symbol": "note.text", "emoji": "📝"},
  {"keys": ["日記", "journal", "diary"], "symbol": "book.closed.fill", "emoji": "📔"},
  {"keys": ["メール", "mail", "email", "emails", "inbox"], "symbol": "envelope.fill", "emoji": "✉️"},
  {"keys": ["連絡先", "住所録", "contact", "contacts", "address"], "symbol": "person.crop.circle.fill", "emoji": "📇"},
  {"keys": ["予定", "カレンダー", "スケジュール", "calendar", "schedule", "events", "agenda"], "symbol": "calendar", "emoji": "📅"},
  {"keys": ["旅行", "旅", "trip", "trips", "travel", "vacation", "holiday", "holidays"], "symbol": "airplane", "emoji": "✈️"},
  {"keys": ["地図", "map", "maps", "gps", "location"], "symbol": "map.fill", "emoji": "🗺️"},
  {"keys": ["家", "自宅", "住まい", "home", "house", "household"], "symbol": "house.fill", "emoji": "🏠"},
  {"keys": ["家族", "family"], "symbol": "figure.2.and.child.holdinghands", "emoji": "👨‍👩‍👧"},
  {"keys": ["子供", "こども", "キッズ", "kids", "children", "baby"], "symbol": "figure.and.child.holdinghands", "emoji": "🧸"},
  {"keys": ["ペット", "犬", "イヌ", "pet", "pets", "dog", "dogs", "puppy"], "symbol": "pawprint.fill", "emoji": "🐶"},
  {"keys": ["猫", "ネコ", "cat", "cats", "kitten"], "symbol": "cat.fill", "emoji": "🐱"},
  {"keys": ["料理", "レシピ", "cooking", "recipe", "recipes", "kitchen"], "symbol": "fork.knife", "emoji": "🍳"},
  {"keys": ["食事", "ごはん", "食べ物", "food", "foods", "meal", "meals", "restaurant", "restaurants"], "symbol": "fork.knife", "emoji": "🍽️"},
  {"keys": ["コーヒー", "カフェ", "coffee", "cafe"], "symbol": "cup.and.saucer.fill", "emoji": "☕"},
  {"keys": ["買い物", "ショッピング", "shopping", "shop", "purchase", "purchases", "orders"], "symbol": "cart.fill", "emoji": "🛒"},
  {"keys": ["健康", "医療", "病院", "health", "medical", "hospital", "doctor"], "symbol": "cross.case.fill", "emoji": "🏥"},
  {"keys": ["運動", "トレーニング", "ジム", "fitness", "workout", "gym", "exercise", "training"], "symbol": "figure.run", "emoji": "🏃"},
  {"keys": ["スポーツ", "sport", "sports"], "symbol": "sportscourt.fill", "emoji": "⚽"},
  {"keys": ["ゲーム", "game", "games", "gaming"], "symbol": "gamecontroller.fill", "emoji": "🎮"},
  {"keys": ["映画", "シネマ", "cinema", "films"], "symbol": "popcorn.fill", "emoji": "🎥"},
  {"keys": ["テレビ", "番組", "tv", "television", "shows", "series"], "symbol": "tv.fill", "emoji": "📺"},
  {"keys": ["カメラ", "撮影", "photography", "shoot", "shooting"], "symbol": "camera.fill", "emoji": "📷"},
  {"keys": ["録音", "ポッドキャスト", "recording", "recordings", "podcast", "podcasts", "voice"], "symbol": "mic.fill", "emoji": "🎙️"},
  {"keys": ["楽譜", "ギター", "ピアノ", "sheet", "guitar", "piano", "band", "instrument"], "symbol": "guitars.fill", "emoji": "🎸"},
  {"keys": ["車", "クルマ", "自動車", "car", "cars", "auto", "vehicle", "garage"], "symbol": "car.fill", "emoji": "🚗"},
  {"keys": ["自転車", "bike", "bicycle", "cycling"], "symbol": "bicycle", "emoji": "🚲"},
  {"keys": ["電車", "鉄道", "train", "trains", "railway"], "symbol": "tram.fill", "emoji": "🚆"},
  {"keys": ["船", "ボート", "boat", "ship", "sailing"], "symbol": "sailboat.fill", "emoji": "⛵"},
  {"keys": ["自然", "山", "登山", "ハイキング", "nature", "mountain", "mountains", "hiking", "outdoor", "outdoors"], "symbol": "mountain.2.fill", "emoji": "⛰️"},
  {"keys": ["海", "ビーチ", "beach", "sea", "ocean"], "symbol": "water.waves", "emoji": "🏖️"},
  {"keys": ["花", "植物", "園芸", "ガーデン", "flower", "flowers", "plant", "plants", "garden", "gardening"], "symbol": "leaf.fill", "emoji": "🌸"},
  {"keys": ["天気", "weather", "climate"], "symbol": "cloud.sun.fill", "emoji": "🌤️"},
  {"keys": ["星", "宇宙", "天体", "star", "stars", "space", "astronomy", "galaxy"], "symbol": "star.fill", "emoji": "⭐"},
  {"keys": ["お気に入", "favorite", "favorites", "favourite", "favourites", "best"], "symbol": "heart.fill", "emoji": "❤️"},
  {"keys": ["重要", "大事", "important", "priority", "urgent"], "symbol": "exclamationmark.circle.fill", "emoji": "❗"},
  {"keys": ["完了", "済み", "done", "finished", "complete", "completed"], "symbol": "checkmark.circle.fill", "emoji": "✅"},
  {"keys": ["作業中", "進行中", "wip", "progress", "ongoing", "current"], "symbol": "hammer.fill", "emoji": "🔨"},
  {"keys": ["下書き", "草稿", "draft", "drafts"], "symbol": "pencil", "emoji": "✏️"},
  {"keys": ["テンプレート", "雛形", "template", "templates"], "symbol": "doc.on.doc.fill", "emoji": "📋"},
  {"keys": ["共有", "shared", "share", "public"], "symbol": "person.2.circle.fill", "emoji": "📤"},
  {"keys": ["個人", "プライベート", "私用", "private", "personal"], "symbol": "lock.fill", "emoji": "🔒"},
  {"keys": ["秘密", "機密", "パスワード", "secret", "secrets", "confidential", "password", "passwords", "keys"], "symbol": "key.fill", "emoji": "🔑"},
  {"keys": ["設定", "config", "configs", "configuration", "settings", "preferences", "dotfiles"], "symbol": "gearshape.fill", "emoji": "⚙️"},
  {"keys": ["ツール", "道具", "tool", "tools", "utilities", "utils"], "symbol": "wrench.and.screwdriver.fill", "emoji": "🧰"},
  {"keys": ["ログ", "log", "logs"], "symbol": "list.bullet.rectangle.fill", "emoji": "📜"},
  {"keys": ["テスト", "test", "tests", "testing", "qa"], "symbol": "checkmark.seal.fill", "emoji": "🧪"},
  {"keys": ["リリース", "release", "releases", "dist", "build", "builds"], "symbol": "shippingbox.fill", "emoji": "📦"},
  {"keys": ["インストール", "installer", "install", "setup", "dmg", "pkg"], "symbol": "square.and.arrow.down.fill", "emoji": "💾"},
  {"keys": ["フォント素材", "素材", "アセット", "asset", "assets", "resources", "resource"], "symbol": "square.stack.3d.up.fill", "emoji": "🧩"},
  {"keys": ["3d", "モデル", "model", "models", "blender", "cad"], "symbol": "cube.fill", "emoji": "🧊"},
  {"keys": ["印刷", "プリント", "print", "prints", "printing"], "symbol": "printer.fill", "emoji": "🖨️"},
  {"keys": ["スキャン", "scan", "scans", "scanned"], "symbol": "scanner.fill", "emoji": "📠"},
  {"keys": ["pdf"], "symbol": "doc.richtext.fill", "emoji": "📄"},
  {"keys": ["zip", "圧縮", "compressed"], "symbol": "doc.zipper", "emoji": "🗜️"},
  {"keys": ["ゴミ", "不要", "trash", "junk", "old", "obsolete", "deprecated"], "symbol": "trash.fill", "emoji": "🗑️"},
  {"keys": ["一時", "仮置き", "temp", "tmp", "temporary", "scratch", "misc", "その他"], "symbol": "tray.fill", "emoji": "📥"},
  {"keys": ["新規", "new", "inbox", "incoming"], "symbol": "tray.and.arrow.down.fill", "emoji": "🆕"},
  {"keys": ["誕生日", "パーティー", "イベント", "birthday", "party", "celebration", "event"], "symbol": "party.popper.fill", "emoji": "🎉"},
  {"keys": ["結婚", "ウェディング", "wedding"], "symbol": "heart.circle.fill", "emoji": "💍"},
  {"keys": ["クリスマス", "christmas", "xmas"], "symbol": "gift.fill", "emoji": "🎄"},
  {"keys": ["正月", "新年", "newyear"], "symbol": "sparkles", "emoji": "🎍"},
  {"keys": ["夏", "summer"], "symbol": "sun.max.fill", "emoji": "☀️"},
  {"keys": ["冬", "雪", "winter", "snow", "ski"], "symbol": "snowflake", "emoji": "❄️"}
]
```

- [ ] **Step 2: テストを書く**

`FolderArtTests/SuggestionDictionaryTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class SuggestionDictionaryTests: XCTestCase {

    func testBundledDictionaryLoadsAndIsWellFormed() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        XCTAssertGreaterThanOrEqual(dict.entries.count, 90)
        for entry in dict.entries {
            XCTAssertFalse(entry.keys.isEmpty)
            XCTAssertTrue(entry.symbol != nil || entry.emoji != nil, "\(entry.keys)")
            for key in entry.keys {
                XCTAssertEqual(key, key.lowercased(), "keys must be lowercase: \(key)")
                // 日本語 (非 ASCII) のキーは 2 文字以上 (誤爆防止)
                if key.unicodeScalars.contains(where: { !$0.isASCII }) {
                    XCTAssertGreaterThanOrEqual(key.count, 2, "Japanese key too short: \(key)")
                }
            }
        }
    }

    func testEverySymbolExistsInCatalogAndIsNotRestricted() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        let names = Set(SymbolCatalog.shared.names)
        for entry in dict.entries {
            if let symbol = entry.symbol {
                XCTAssertTrue(names.contains(symbol), "unknown or restricted symbol: \(symbol)")
            }
        }
    }

    func testMissingResourceGivesEmptyDictionary() {
        let dict = SuggestionDictionary.load(bundle: Bundle(path: "/nonexistent") ?? Bundle(for: SuggestionDictionaryTests.self),
                                             resourceName: "does-not-exist")
        XCTAssertEqual(dict, .empty)
    }
}
```

- [ ] **Step 3: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionDictionaryTests`)
Expected: ビルドエラー (`SuggestionDictionary` 未定義)

- [ ] **Step 4: 実装**

`FolderArt/Services/SuggestionDictionary.swift`:

```swift
import Foundation

/// 「語 → 記号名・絵文字」の 1 項目。keys は小文字、日本語は 2 文字以上。
struct SuggestionEntry: Codable, Equatable, Sendable {
    let keys: [String]
    let symbol: String?
    let emoji: String?
}

/// 同梱の suggestions.json。読めなければ空 (提案は規則と検索語だけで動く)。
struct SuggestionDictionary: Equatable {
    let entries: [SuggestionEntry]

    static let empty = SuggestionDictionary(entries: [])

    init(entries: [SuggestionEntry]) {
        self.entries = entries
    }

    static func load(bundle: Bundle = .main, resourceName: String = "suggestions") -> SuggestionDictionary {
        for b in [bundle, Bundle.main] {
            if let url = b.url(forResource: resourceName, withExtension: "json"),
               let data = try? Data(contentsOf: url),
               let entries = try? JSONDecoder().decode([SuggestionEntry].self, from: data) {
                return SuggestionDictionary(entries: entries)
            }
        }
        return .empty
    }
}
```

`testEverySymbolExistsInCatalogAndIsNotRestricted` が落ちた記号名は、その名前をこの macOS の `SymbolCatalog.shared.names` に存在するものへ置き換える (例: `figure.2.and.child.holdinghands` が無ければ `person.3.fill`)。制限付き記号 (Apple 製品・機能) は使わない。

- [ ] **Step 5: プロジェクト再生成とテスト**

Run: `xcodegen generate` → `grep -c "suggestions.json" FolderArt.xcodeproj/project.pbxproj` が 1 以上 → テスト実行 (`-only-testing:FolderArtTests/SuggestionDictionaryTests`)
Expected: 3 tests PASS

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Services/SuggestionDictionary.swift FolderArt/Resources/suggestions.json FolderArtTests/SuggestionDictionaryTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ 提案辞書 (suggestions.json) と読み込みを追加"
```

---

### Task 2: SuggestionEngine (提案の計算)

**Files:**
- Create: `FolderArt/Models/Suggestion.swift`
- Create: `FolderArt/Services/SuggestionEngine.swift`
- Modify: `FolderArt/Services/SymbolCatalog.swift` (検索語の逆引き `names(forTerm:)` を追加)
- Test: `FolderArtTests/SuggestionEngineTests.swift`

**Interfaces:**
- Consumes: `SuggestionDictionary`, `SymbolCatalog` (`names`, `searchTerms`), `Preset`
- Produces:
  ```swift
  struct Suggestion: Equatable, Identifiable {
      enum Kind: Equatable { case symbol(String), emoji(String), text(String), preset(Preset) }
      let kind: Kind
      let reason: String
      var id: String
  }
  struct SuggestionEngine {
      init(dictionary: SuggestionDictionary, catalog: SymbolCatalog)
      func suggest(for folderName: String, presets: [Preset]) -> [Suggestion]   // 最大 3、[記号/お気に入り, 絵文字, 文字] の順
      static func normalize(_ s: String) -> String                                // NFKC + 小文字
      static func latinTokens(_ normalized: String) -> [String]
  }
  extension SymbolCatalog { func names(forTerm term: String) -> [String] }        // 検索語 == term の記号名 (アルファベット順)
  ```

- [ ] **Step 1: テストを書く**

`FolderArtTests/SuggestionEngineTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class SuggestionEngineTests: XCTestCase {

    private let dict = SuggestionDictionary(entries: [
        SuggestionEntry(keys: ["写真", "photo", "photos"], symbol: "photo.fill", emoji: "📷"),
        SuggestionEntry(keys: ["請求書", "invoice"], symbol: "doc.text.fill", emoji: "🧾"),
        SuggestionEntry(keys: ["音楽", "music"], symbol: "music.note", emoji: "🎵"),
        SuggestionEntry(keys: ["設定", "config"], symbol: "gearshape.fill", emoji: nil),
    ])
    private let catalog = SymbolCatalog(
        names: ["photo.fill", "doc.text.fill", "music.note", "gearshape.fill", "figure.run", "star.fill"],
        searchTerms: ["figure.run": ["running", "sports"], "star.fill": ["favorite"]])
    private var engine: SuggestionEngine { SuggestionEngine(dictionary: dict, catalog: catalog) }

    func testNormalizeFoldsWidthAndCase() {
        XCTAssertEqual(SuggestionEngine.normalize("Ｐｈｏｔｏ　２０２５"), "photo 2025")
        XCTAssertEqual(SuggestionEngine.latinTokens("photo_2025-final.v2 (draft)"), ["photo", "2025", "final", "v2", "draft"])
        XCTAssertEqual(SuggestionEngine.latinTokens(SuggestionEngine.normalize("myPhotoAlbum")), ["my", "photo", "album"])
    }

    func testEnglishWordHitsDictionary() {
        let s = engine.suggest(for: "Photos 2024", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("photo.fill"), .emoji("📷"), .text("2024")])
    }

    func testJapaneseSubstringHitsDictionaryLongestFirst() {
        let s = engine.suggest(for: "2025年 請求書 控え", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("doc.text.fill"), .emoji("🧾"), .text("2025")])
    }

    func testJapaneseKeyDoesNotMatchInsideUnrelatedWord() {
        // 「設定」は含まれない。「定」だけ、「設」だけの語には当たらない
        let s = engine.suggest(for: "予定表", presets: [])
        XCTAssertTrue(s.isEmpty)
    }

    func testFavoriteWinsTheSymbolSlot() {
        let preset = Preset(name: "photo", overlay: .text("P"), settings: CompositionSettings())
        let s = engine.suggest(for: "photo backup", presets: [preset])
        XCTAssertEqual(s.first?.kind, .preset(preset))
        XCTAssertEqual(s.count, 2)                       // お気に入り + 絵文字 (辞書)、記号枠は使われ済み
        XCTAssertEqual(s[1].kind, .emoji("📷"))
    }

    func testSearchTermFallbackWhenDictionaryMisses() {
        let s = engine.suggest(for: "Sports club", presets: [])
        XCTAssertEqual(s.map(\.kind), [.symbol("figure.run")])
    }

    func testRulesProduceTextForYearsAndShortCodes() {
        XCTAssertEqual(engine.suggest(for: "2026", presets: []).map(\.kind), [.text("2026")])
        XCTAssertEqual(engine.suggest(for: "Q3 reports", presets: []).map(\.kind), [.text("Q3")])
        XCTAssertTrue(engine.suggest(for: "12345", presets: []).isEmpty)   // 5 桁は対象外
    }

    func testAtMostThreeAndNoDuplicateKinds() {
        // 辞書で記号+絵文字、規則で文字。合計 3 を超えない
        let s = engine.suggest(for: "music photo 2024 A", presets: [])
        XCTAssertEqual(s.count, 3)
        XCTAssertEqual(s[0].kind, .symbol("music.note"))   // 最初に当たった語の記号
        XCTAssertEqual(s[1].kind, .emoji("🎵"))
        XCTAssertEqual(s[2].kind, .text("2024"))
    }

    func testEmptyWhenNothingMatches() {
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: []).isEmpty)
        XCTAssertTrue(engine.suggest(for: "", presets: []).isEmpty)
    }

    func testIdsAreStable() {
        let a = engine.suggest(for: "photo", presets: [])
        let b = engine.suggest(for: "photo", presets: [])
        XCTAssertEqual(a.map(\.id), b.map(\.id))
        XCTAssertEqual(a.first?.id, "symbol:photo.fill")
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionEngineTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Models/Suggestion.swift`:

```swift
import Foundation

/// フォルダ名から導いた候補 1 つ。
struct Suggestion: Equatable, Identifiable {
    enum Kind: Equatable {
        case symbol(String)
        case emoji(String)
        case text(String)
        case preset(Preset)
    }

    let kind: Kind
    /// ツールチップ用 (例: 「"photo" に一致」)
    let reason: String

    var id: String {
        switch kind {
        case .symbol(let s): return "symbol:\(s)"
        case .emoji(let s):  return "emoji:\(s)"
        case .text(let s):   return "text:\(s)"
        case .preset(let p): return "preset:\(p.id.uuidString)"
        }
    }
}
```

`FolderArt/Services/SymbolCatalog.swift` に追加 (struct 内の `search` の後):

```swift
    /// 検索語 (symbol_search.plist) が term に一致する記号名。アルファベット順。
    func names(forTerm term: String) -> [String] {
        let t = term.lowercased()
        return searchTerms
            .filter { $0.value.contains { $0.lowercased() == t } }
            .map(\.key)
            .filter { names.contains($0) }
            .sorted()
    }
```

`names.contains` は `[String]` の線形探索なので、`SymbolCatalog` に `let nameSet: Set<String>` (internal。別ファイルの extension からは private が見えないため) を持たせ、明示的な `init(names:searchTerms:)` で `nameSet = Set(names)` を設定する (既存の memberwise 形のテストはそのまま通る)。`names(forTerm:)` と `search` の `set` もこれを使う。あわせて **`SymbolCatalog.swift` の struct 本体に** 次を足す (SuggestionEngine 側の extension には書かない):

```swift
    func contains(_ name: String) -> Bool { nameSet.contains(name) }
```

`FolderArt/Services/SuggestionEngine.swift`:

```swift
import Foundation

/// フォルダ名から候補を作る純関数。優先順: お気に入り → 辞書 → SF Symbols の検索語 → 規則。
struct SuggestionEngine {
    let dictionary: SuggestionDictionary
    let catalog: SymbolCatalog

    init(dictionary: SuggestionDictionary, catalog: SymbolCatalog) {
        self.dictionary = dictionary
        self.catalog = catalog
    }

    func suggest(for folderName: String, presets: [Preset]) -> [Suggestion] {
        let normalized = Self.normalize(folderName)
        guard !normalized.isEmpty else { return [] }
        let tokens = Self.latinTokens(normalized)

        var symbol: Suggestion?
        var emoji: Suggestion?
        var text: Suggestion?

        // 1. お気に入り (名前がフォルダ名に含まれる) は記号枠で最優先
        for preset in presets {
            let key = Self.normalize(preset.name)
            guard key.count >= 2, normalized.contains(key) else { continue }
            symbol = Suggestion(kind: .preset(preset), reason: String(localized: "お気に入り「\(preset.name)」"))
            break
        }

        // 2. 辞書: 一致した項目を「当たったキーの長い順、同じ長さならフォルダ名の先に出た順」に並べる
        //    (sort は安定でないので位置で決定的にする)
        var hits: [(key: String, position: Int, entry: SuggestionEntry)] = []
        for entry in dictionary.entries {
            for key in entry.keys {
                let isLatin = key.unicodeScalars.allSatisfy { $0.isASCII }
                let matched = isLatin ? tokens.contains(key) : normalized.contains(key)
                if matched {
                    let position = normalized.range(of: key).map { normalized.distance(from: normalized.startIndex, to: $0.lowerBound) } ?? Int.max
                    hits.append((key, position, entry)); break
                }
            }
        }
        hits.sort { ($0.key.count, -$0.position) > ($1.key.count, -$1.position) }
        for hit in hits {
            if symbol == nil, let name = hit.entry.symbol, catalog.contains(name) {
                symbol = Suggestion(kind: .symbol(name), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if emoji == nil, let e = hit.entry.emoji {
                emoji = Suggestion(kind: .emoji(e), reason: String(localized: "「\(hit.key)」に一致"))
            }
            if symbol != nil && emoji != nil { break }
        }

        // 3. SF Symbols の検索語 (辞書に無い英単語)
        if symbol == nil {
            for token in tokens where token.count >= 3 {
                if catalog.contains(token) {
                    symbol = Suggestion(kind: .symbol(token), reason: String(localized: "記号名「\(token)」"))
                    break
                }
                if let name = catalog.names(forTerm: token).first {
                    symbol = Suggestion(kind: .symbol(name), reason: String(localized: "検索語「\(token)」に一致"))
                    break
                }
            }
        }

        // 4. 規則: 4 桁の数字、2 文字以内の英数字 → 文字
        for token in tokens {
            if Self.isYear(token) || Self.isShortCode(token) {
                let value = Self.isShortCode(token) ? token.uppercased() : token
                text = Suggestion(kind: .text(value), reason: String(localized: "フォルダ名の「\(value)」"))
                break
            }
        }

        return [symbol, emoji, text].compactMap { $0 }
    }

    // MARK: - 正規化と分割

    /// NFKC (全角英数字 → 半角、半角カナ → 全角カナ) + 小文字
    static func normalize(_ s: String) -> String {
        s.precomposedStringWithCompatibilityMapping.lowercased()
    }

    /// 空白・記号・camelCase の境界で切った英数字の語 (小文字)
    static func latinTokens(_ normalized: String) -> [String] {
        // camelCase の境界に空白を入れてから分割する。normalize 済み (小文字) の文字列には
        // 大文字が残らないので、ここでは元の大文字情報を使えない → 呼び出し側で normalize 前に
        // 境界を入れる必要があるが、単純化のため正規化前後の両方で処理できるよう「小文字→大文字」
        // 境界は normalize の前に扱う (下の split を参照)
        var out: [String] = []
        var current = ""
        for ch in normalized {
            if ch.isLetter || ch.isNumber, ch.isASCII {
                current.append(ch)
            } else if ch.isASCII || ch.isWhitespace || ch.isPunctuation || ch.isSymbol {
                if !current.isEmpty { out.append(current); current = "" }
            } else {
                // 日本語などはトークンにしない (辞書は部分文字列で当てる)
                if !current.isEmpty { out.append(current); current = "" }
            }
        }
        if !current.isEmpty { out.append(current) }
        return out
    }

    static func isYear(_ token: String) -> Bool {
        token.count == 4 && token.allSatisfy(\.isNumber)
    }

    static func isShortCode(_ token: String) -> Bool {
        (1...2).contains(token.count) && token.allSatisfy { $0.isLetter || $0.isNumber }
    }
}

```

camelCase の分割 (`myPhotoAlbum` → `my photo album`) は `normalize` の前に行う必要があるので、`normalize` を次のように実装する (小文字化の前に「小文字/数字 → 大文字」の境界へ空白を挿入):

```swift
    static func normalize(_ s: String) -> String {
        var spaced = ""
        var previous: Character?
        for ch in s {
            if let p = previous, ch.isUppercase, (p.isLowercase || p.isNumber) { spaced.append(" ") }
            spaced.append(ch)
            previous = ch
        }
        return spaced.precomposedStringWithCompatibilityMapping.lowercased()
    }
```

`testNormalizeFoldsWidthAndCase` の 1 つ目の期待値は `"photo 2025"` (全角空白は NFKC で半角空白になる)。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/SuggestionEngineTests -only-testing:FolderArtTests/SymbolCatalogTests`)
Expected: 10 + 既存 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/Suggestion.swift FolderArt/Services/SuggestionEngine.swift FolderArt/Services/SymbolCatalog.swift FolderArtTests/SuggestionEngineTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ SuggestionEngine を追加 (お気に入り → 辞書 → 検索語 → 規則)"
```

---

### Task 3: 提案の帯 (SuggestionStripView) と AppModel の配線

**Files:**
- Create: `FolderArt/Views/SuggestionStripView.swift`
- Modify: `FolderArt/AppModel.swift` (`suggestions`、`applySuggestion`、フォルダ選択とお気に入りの購読)
- Modify: `FolderArt/Views/OverlayPickerView.swift` (タブの上に帯)
- Modify: `FolderArt/ContentView.swift` (配線)
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `SuggestionEngine`, `Suggestion`, `OverlayState` (`activeTab`, `symbolName`, `emoji`, `text`), `AppModel.applyPreset`
- Produces:
  - `AppModel`: `@Published private(set) var suggestions: [Suggestion]`, `func applySuggestion(_ s: Suggestion)`, `var suggestionSourceFolder: URL?` (選択があれば選択中のうちリスト順で最後、無ければ `folders.last`)
  - `struct SuggestionStripView: View { let suggestions: [Suggestion]; let assets: AssetStore; let isApplying: Bool; let onPick: (Suggestion) -> Void }` (高さ 36pt 固定)
  - `OverlayPickerView` に `suggestions: [Suggestion]` と `onPickSuggestion: (Suggestion) -> Void` を追加

- [ ] **Step 1: テストを書く**

`FolderArtTests/AppModelTests.swift` に追加 (既存の `setUp` の `root` / `model` を使う):

```swift
    /// 提案は「選択中の行 (リスト順で最後)、無ければ最後に追加した行」の名前から作る
    func testSuggestionsFollowSelectedOrLastFolder() throws {
        let photos = root.appendingPathComponent("Photos")
        let invoices = root.appendingPathComponent("請求書")
        for d in [photos, invoices] { try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true) }

        model.addFolders([photos])
        XCTAssertEqual(model.suggestionSourceFolder, photos.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("📷") })

        model.addFolders([invoices])
        XCTAssertEqual(model.suggestionSourceFolder, invoices.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("🧾") })

        model.folders.selectedIDs = [photos.standardizedFileURL]
        XCTAssertEqual(model.suggestionSourceFolder, photos.standardizedFileURL)
        XCTAssertTrue(model.suggestions.contains { $0.kind == .emoji("📷") })

        model.folders.removeAll()
        XCTAssertNil(model.suggestionSourceFolder)
        XCTAssertTrue(model.suggestions.isEmpty)
    }

    /// 候補を押すとそのタブに切り替わって入力が入る。設定は変えない
    func testApplySuggestionSwitchesTabAndInput() throws {
        let before = model.overlay.settings
        model.applySuggestion(Suggestion(kind: .symbol("star.fill"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .symbol)
        XCTAssertEqual(model.overlay.symbolName, "star.fill")
        model.applySuggestion(Suggestion(kind: .emoji("🎵"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .emoji)
        XCTAssertEqual(model.overlay.emoji, "🎵")
        model.applySuggestion(Suggestion(kind: .text("2026"), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .text)
        XCTAssertEqual(model.overlay.text, "2026")
        XCTAssertEqual(model.overlay.settings, before)

        var settings = CompositionSettings(); settings.position = .badge
        let preset = Preset(name: "p", overlay: .symbol(name: "heart.fill"), settings: settings)
        model.applySuggestion(Suggestion(kind: .preset(preset), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .symbol)
        XCTAssertEqual(model.overlay.settings.position, .badge)   // お気に入りだけは設定まで復元
    }

    /// お気に入りの名前がフォルダ名に含まれると、その お気に入りが提案される
    func testPresetNameInFolderNameIsSuggested() throws {
        let d = root.appendingPathComponent("旅行 2025")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true)
        try model.presets.add(name: "旅行", overlay: .emoji("✈️"), settings: CompositionSettings())
        model.addFolders([d])
        guard case .preset(let p)? = model.suggestions.first?.kind else { return XCTFail("preset first") }
        XCTAssertEqual(p.name, "旅行")
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: ビルドエラー (`suggestions` 未定義)

- [ ] **Step 3: AppModel を実装**

`FolderArt/AppModel.swift` に追加。プロパティ:

```swift
    /// 提案 (フォルダ名から)。空なら帯はチップ無しで高さだけ保つ
    @Published private(set) var suggestions: [Suggestion] = []
    private let suggestionEngine: SuggestionEngine
```

`init` の引数に `suggestionEngine: SuggestionEngine = SuggestionEngine(dictionary: SuggestionDictionary.load(), catalog: SymbolCatalog.shared)` を追加し、`self.suggestionEngine = suggestionEngine` を代入。`init` の末尾 (`reapAssets()` の前) に購読を足す:

```swift
        // フォルダの増減・選択・お気に入りの変化で提案を作り直す (同期・純関数なのでデバウンス不要)
        Publishers.CombineLatest3(folders.$folders, folders.$selectedIDs, presets.$presets)
            .sink { [weak self] _, _, _ in self?.refreshSuggestions() }
            .store(in: &cancellables)
```

メソッド (`// MARK: - お気に入り` の前に `// MARK: - 提案` を作る):

```swift
    // MARK: - 提案

    /// 提案の元になるフォルダ: 選択があれば選択中のうちリスト順で最後のもの、無ければ最後に追加した行
    var suggestionSourceFolder: URL? {
        let selected = folders.folders.filter { folders.selectedIDs.contains($0) }
        return selected.last ?? folders.folders.last
    }

    private func refreshSuggestions() {
        guard let folder = suggestionSourceFolder else { suggestions = []; return }
        suggestions = suggestionEngine.suggest(for: folder.lastPathComponent, presets: presets.presets)
    }

    /// 候補を採用する。記号・絵文字・文字はタブと入力だけ変え、設定は触らない。お気に入りは設定まで復元。
    func applySuggestion(_ suggestion: Suggestion) {
        guard !isApplying else { return }
        switch suggestion.kind {
        case .symbol(let name): overlay.activeTab = .symbol; overlay.symbolName = name
        case .emoji(let e):     overlay.activeTab = .emoji;  overlay.emoji = e
        case .text(let t):      overlay.activeTab = .text;   overlay.text = t
        case .preset(let p):    applyPreset(p)
        }
    }
```

`CombineLatest3` の `folders.$folders` / `folders.$selectedIDs` は `FolderSelection` の `@Published` から取れる (`folders` は `private(set)` だが `$folders` は読める)。`presets.$presets` も同様。

- [ ] **Step 4: SuggestionStripView を実装**

`FolderArt/Views/SuggestionStripView.swift`:

```swift
import SwiftUI

/// タブの上に出す提案の帯。高さ 36pt 固定 (候補が無くても空のまま高さを保つ)。
struct SuggestionStripView: View {
    let suggestions: [Suggestion]
    let assets: AssetStore
    let isApplying: Bool
    let onPick: (Suggestion) -> Void

    var body: some View {
        HStack(spacing: 6) {
            if !suggestions.isEmpty {
                Text("提案:").font(.caption).foregroundColor(.secondary)
                ForEach(suggestions) { s in
                    SuggestionChip(suggestion: s, assets: assets)
                        .onTapGesture { guard !isApplying else { return }; onPick(s) }
                        .opacity(isApplying ? 0.5 : 1)
                        .help(Text(s.reason))
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: 36)
        .padding(.horizontal, 4)
    }
}

/// 候補 1 つ分のチップ (32pt のサムネイル + 短いラベル)。サムネイルは 1 回だけ描いてキャッシュ。
private struct SuggestionChip: View {
    let suggestion: Suggestion
    let assets: AssetStore
    @State private var cached: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let image = cached {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "sparkles").foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            Text(label).font(.caption).lineLimit(1)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))
        .task(id: suggestion.id) { cached = thumbnail }
    }

    private var label: String {
        switch suggestion.kind {
        case .symbol(let s): return s
        case .emoji(let e):  return e
        case .text(let t):   return t
        case .preset(let p): return p.name
        }
    }

    private var thumbnail: NSImage? {
        let (overlay, settings): (Overlay, CompositionSettings) = {
            switch suggestion.kind {
            case .symbol(let s): return (.symbol(name: s), CompositionSettings())
            case .emoji(let e):  return (.emoji(e), CompositionSettings())
            case .text(let t):   return (.text(t), CompositionSettings())
            case .preset(let p): return (p.overlay, p.settings)
            }
        }()
        guard let rendered = OverlayRenderer.render(overlay, settings: settings, side: 128, assets: assets) else { return nil }
        return IconComposer.compose(overlay: rendered, settings: settings, fillsWhenClipped: overlay.fillsFolderWhenClipped)
    }
}
```

- [ ] **Step 5: OverlayPickerView と ContentView を配線**

`FolderArt/Views/OverlayPickerView.swift`: プロパティに `let suggestions: [Suggestion]` と `let onPickSuggestion: (Suggestion) -> Void` を足し、`body` の `VStack(spacing: 8) {` 直後 (`Picker` の前) に:

```swift
            SuggestionStripView(suggestions: suggestions, assets: state.assets,
                                isApplying: false, onPick: onPickSuggestion)
```

(`isApplying` は `OverlayPickerView` が持っていないので、`OverlayPickerView` にも `var isApplying: Bool = false` を足して渡す。)

`FolderArt/ContentView.swift` の `OverlayPickerView(...)` 呼び出しに `suggestions: model.suggestions, isApplying: model.isApplying, onPickSuggestion: { model.applySuggestion($0) }` を追加。`.frame(height: 260)` は帯の分 `.frame(height: 296)` にする。

- [ ] **Step 6: テストとビルド**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: AppModelTests の新規 3 件を含め全 PASS。プロジェクト由来の警告 0。

- [ ] **Step 7: コミット**

```bash
git add FolderArt/Views/SuggestionStripView.swift FolderArt/AppModel.swift FolderArt/Views/OverlayPickerView.swift FolderArt/ContentView.swift FolderArtTests/AppModelTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ フォルダ名からの提案をタブの上に表示し、クリックで採用できるようにする"
```

---

### Task 4: パックの形式 (Pack / PackWriter / PackReader)

**Files:**
- Create: `FolderArt/Models/Pack.swift`
- Create: `FolderArt/Services/PackWriter.swift`
- Create: `FolderArt/Services/PackReader.swift`
- Test: `FolderArtTests/PackTests.swift`

**Interfaces:**
- Consumes: `Preset`, `Overlay`, `CompositionSettings`, `AssetStore.url(for:)` / `image(for:)`
- Produces:
  ```swift
  struct PackEntry: Codable, Equatable { var name: String; var overlay: Overlay; var settings: CompositionSettings; var image: Data? }
  struct Pack: Codable, Equatable { static let currentFormat = 1; var format: Int; var app: String; var appVersion: String; var exportedAt: Date; var presets: [PackEntry] }
  enum PackError: LocalizedError { case unsupportedFormat(Int), corrupted, tooManyPresets(Int), invalidImage(String), missingImage(String) }
  struct ImportSummary: Equatable { var added: Int; var skippedIdentical: Int }
  enum PackWriter { static let maxPresets = 200; static func write(_ presets: [Preset], assets: AssetStore, appVersion: String) throws -> Data }
  enum PackReader { static func read(_ data: Data) throws -> Pack }   // 形式・件数・画像の検証込み
  ```
- 日付は ISO 8601 (`JSONEncoder.dateEncodingStrategy = .iso8601`)。

- [ ] **Step 1: テストを書く**

`FolderArtTests/PackTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class PackTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PackTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func makePresets() throws -> [Preset] {
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 40, height: 20), color: .red))
        var badge = CompositionSettings(); badge.position = .badge
        return [
            Preset(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings()),
            Preset(name: "26", overlay: .text("26"), settings: badge),
            Preset(name: "ロゴ", overlay: .image(assetID: id), settings: CompositionSettings()),
        ]
    }

    func testRoundTripKeepsEntriesAndEmbedsImage() throws {
        let presets = try makePresets()
        let data = try PackWriter.write(presets, assets: assets, appVersion: "1.3.0")
        let pack = try PackReader.read(data)
        XCTAssertEqual(pack.format, Pack.currentFormat)
        XCTAssertEqual(pack.app, "FolderArt")
        XCTAssertEqual(pack.appVersion, "1.3.0")
        XCTAssertEqual(pack.presets.map(\.name), ["星", "26", "ロゴ"])
        XCTAssertEqual(pack.presets[1].settings.position, .badge)
        XCTAssertNil(pack.presets[0].image)
        let png = try Data(contentsOf: assets.url(for: presets[2].overlay.assetID!))
        XCTAssertEqual(pack.presets[2].image, png)
        // id と createdAt は書き出さない
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("createdAt"))
        XCTAssertFalse(json.contains("\"id\""))
    }

    func testRejectsUnsupportedFormat() throws {
        let data = try PackWriter.write([], assets: assets, appVersion: "1.3.0")
        let bumped = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2")
        XCTAssertThrowsError(try PackReader.read(bumped.data(using: .utf8)!)) { error in
            guard case PackError.unsupportedFormat(2) = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsCorruptJSON() {
        XCTAssertThrowsError(try PackReader.read("not json".data(using: .utf8)!)) { error in
            guard case PackError.corrupted = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsTooManyPresets() throws {
        let many = (0..<201).map { Preset(name: "p\($0)", overlay: .text("\($0)"), settings: CompositionSettings()) }
        let data = try PackWriter.write(many, assets: assets, appVersion: "1.3.0")
        XCTAssertThrowsError(try PackReader.read(data)) { error in
            guard case PackError.tooManyPresets(201) = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsImagePresetWithoutOrInvalidImage() throws {
        var pack = Pack(format: 1, app: "FolderArt", appVersion: "1.3.0", exportedAt: Date(),
                        presets: [PackEntry(name: "x", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: nil)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.missingImage("x") = error else { return XCTFail("\(error)") }
        }
        pack.presets[0].image = "not a png".data(using: .utf8)
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.invalidImage("x") = error else { return XCTFail("\(error)") }
        }
        // PNG 以外の画像形式 (TIFF) も拒否する
        pack.presets[0].image = TestSupport.makeSolidImage(size: CGSize(width: 4, height: 4), color: .red).tiffRepresentation
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.invalidImage("x") = error else { return XCTFail("\(error)") }
        }
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/PackTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Models/Pack.swift`:

```swift
import Foundation

/// パックの 1 項目。id と createdAt は持たない (受け取り側で振り直す)。
struct PackEntry: Codable, Equatable {
    var name: String
    var overlay: Overlay
    var settings: CompositionSettings
    /// overlay が .image のときだけ PNG (Base64 で JSON に入る)
    var image: Data?
}

struct Pack: Codable, Equatable {
    static let currentFormat = 1
    var format: Int
    var app: String
    var appVersion: String
    var exportedAt: Date
    var presets: [PackEntry]
}

enum PackError: LocalizedError, Equatable {
    case unsupportedFormat(Int)
    case corrupted
    case tooManyPresets(Int)
    case missingImage(String)
    case invalidImage(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "このパックは新しいバージョンの FolderArt で作られています。")
        case .corrupted:
            return String(localized: "パックを読み込めません (ファイルが壊れています)。")
        case .tooManyPresets(let n):
            return String(localized: "パックの項目が多すぎます (\(n) 件、上限 \(PackWriter.maxPresets) 件)。")
        case .missingImage(let name):
            return String(localized: "「\(name)」の画像がパックに含まれていません。")
        case .invalidImage(let name):
            return String(localized: "「\(name)」の画像を読み込めません。")
        }
    }
}

struct ImportSummary: Equatable {
    var added: Int
    var skippedIdentical: Int
}
```

`FolderArt/Services/PackWriter.swift`:

```swift
import Foundation

enum PackWriter {
    static let maxPresets = 200

    static func write(_ presets: [Preset], assets: AssetStore, appVersion: String) throws -> Data {
        let entries: [PackEntry] = try presets.map { preset in
            var image: Data?
            if let id = preset.overlay.assetID {
                image = try Data(contentsOf: assets.url(for: id))
            }
            return PackEntry(name: preset.name, overlay: preset.overlay, settings: preset.settings, image: image)
        }
        let pack = Pack(format: Pack.currentFormat, app: "FolderArt", appVersion: appVersion,
                        exportedAt: Date(), presets: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(pack)
    }
}
```

`FolderArt/Services/PackReader.swift`:

```swift
import AppKit

enum PackReader {
    /// JSON を読み、形式・件数・画像を検証する。1 件でも不正ならパック全体を拒否。
    static func read(_ data: Data) throws -> Pack {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // format だけ先に見て、未対応なら「新しいバージョン」と伝える
        struct Header: Decodable { let format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw PackError.corrupted }
        guard header.format == Pack.currentFormat else { throw PackError.unsupportedFormat(header.format) }
        guard let pack = try? decoder.decode(Pack.self, from: data) else { throw PackError.corrupted }
        guard pack.presets.count <= PackWriter.maxPresets else { throw PackError.tooManyPresets(pack.presets.count) }
        for entry in pack.presets where entry.overlay.assetID != nil {
            guard let image = entry.image else { throw PackError.missingImage(entry.name) }
            guard isPNG(image), NSImage(data: image) != nil else { throw PackError.invalidImage(entry.name) }
        }
        return pack
    }

    /// PNG のシグネチャ (89 50 4E 47 0D 0A 1A 0A) で始まるか。パックの画像は PNG だけを受け付ける
    static func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/PackTests`)
Expected: 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/Pack.swift FolderArt/Services/PackWriter.swift FolderArt/Services/PackReader.swift FolderArtTests/PackTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ お気に入りパックの形式 (Pack) と書き出し・読み込みを追加"
```

---

### Task 5: PresetStore.addAll と PresetImporter

**Files:**
- Modify: `FolderArt/Stores/PresetStore.swift` (`addAll`)
- Create: `FolderArt/Services/PresetImporter.swift`
- Test: `FolderArtTests/PresetStoreTests.swift`, `FolderArtTests/PresetImporterTests.swift`

**Interfaces:**
- Consumes: `Pack`, `PackEntry`, `PresetStore` (`presets`, `defaultName(for:existing:)`), `AssetStore.store(_:)` / `remove(_:)`
- Produces:
  - `PresetStore.addAll(_ presets: [Preset]) throws` (先頭に順序どおり挿入、保存 1 回、失敗時は 1 件も入らない)
  - `enum PresetImporter { static func importPack(_ pack: Pack, into store: PresetStore, assets: AssetStore) throws -> ImportSummary }`

- [ ] **Step 1: テストを書く**

`FolderArtTests/PresetStoreTests.swift` に追加:

```swift
    func testAddAllInsertsInOrderWithOneSave() throws {
        try store.add(name: "old", overlay: .text("o"), settings: CompositionSettings())
        let a = Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())
        let b = Preset(name: "b", overlay: .text("b"), settings: CompositionSettings())
        try store.addAll([a, b])
        XCTAssertEqual(store.presets.map(\.name), ["a", "b", "old"])
        XCTAssertEqual(PresetStore(storageURL: url).presets.map(\.name), ["a", "b", "old"])
    }

    func testAddAllIsAllOrNothing() throws {
        // 保存先を書けなくして addAll → メモリにもファイルにも増えない
        let locked = url.deletingLastPathComponent().appendingPathComponent("locked_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let s = PresetStore(storageURL: locked.appendingPathComponent("presets.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try s.addAll([Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())]))
        XCTAssertTrue(s.presets.isEmpty)
    }
```

`FolderArtTests/PresetImporterTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class PresetImporterTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!
    private var store: PresetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ImporterTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir.appendingPathComponent("assets"))
        store = PresetStore(storageURL: dir.appendingPathComponent("presets.json"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func pack(_ entries: [PackEntry]) -> Pack {
        Pack(format: 1, app: "FolderArt", appVersion: "1.3.0", exportedAt: Date(), presets: entries)
    }
    private func png() -> Data { TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .green)) }

    func testAddsEntriesAndRenamesDuplicates() throws {
        try store.add(name: "星", overlay: .text("x"), settings: CompositionSettings())
        let summary = try PresetImporter.importPack(pack([
            PackEntry(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings(), image: nil),
            PackEntry(name: "月", overlay: .emoji("🌙"), settings: CompositionSettings(), image: nil),
        ]), into: store, assets: assets)
        XCTAssertEqual(summary, ImportSummary(added: 2, skippedIdentical: 0))
        XCTAssertEqual(store.presets.map(\.name), ["星 2", "月", "星"])
    }

    func testSkipsIdenticalAgainstExistingAndWithinPack() throws {
        try store.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let e = PackEntry(name: "star", overlay: .symbol(name: "star.fill"), settings: CompositionSettings(), image: nil)
        let summary = try PresetImporter.importPack(pack([e, e, PackEntry(name: "月", overlay: .emoji("🌙"), settings: CompositionSettings(), image: nil)]),
                                                    into: store, assets: assets)
        XCTAssertEqual(summary, ImportSummary(added: 1, skippedIdentical: 2))
        XCTAssertEqual(store.presets.map(\.name), ["月", "星"])
    }

    func testIdenticalImageEntriesAreSkippedByPixels() throws {
        let entry = PackEntry(name: "ロゴ", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: png())
        let first = try PresetImporter.importPack(pack([entry, entry]), into: store, assets: assets)
        XCTAssertEqual(first, ImportSummary(added: 1, skippedIdentical: 1))
        // 同じパックをもう一度読み込んでも増えない (既存のお気に入りの PNG と一致)
        let second = try PresetImporter.importPack(pack([entry]), into: store, assets: assets)
        XCTAssertEqual(second, ImportSummary(added: 0, skippedIdentical: 1))
        XCTAssertEqual(assets.allIDs().count, 1)
    }

    func testImageEntryIsCopiedIntoAssetsWithNewID() throws {
        let stale = UUID()
        let summary = try PresetImporter.importPack(pack([
            PackEntry(name: "ロゴ", overlay: .image(assetID: stale), settings: CompositionSettings(), image: png()),
        ]), into: store, assets: assets)
        XCTAssertEqual(summary.added, 1)
        let id = try XCTUnwrap(store.presets.first?.overlay.assetID)
        XCTAssertNotEqual(id, stale)
        XCTAssertNotNil(assets.image(for: id))
    }

    func testFailedSaveLeavesNoAssetsBehind() throws {
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let lockedStore = PresetStore(storageURL: locked.appendingPathComponent("presets.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try PresetImporter.importPack(pack([
            PackEntry(name: "ロゴ", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: png()),
        ]), into: lockedStore, assets: assets))
        XCTAssertTrue(lockedStore.presets.isEmpty)
        XCTAssertTrue(assets.allIDs().isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/PresetStoreTests -only-testing:FolderArtTests/PresetImporterTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Stores/PresetStore.swift` に追加 (`add` の後):

```swift
    /// 複数件を先頭に順序どおり挿入し、保存は 1 回。保存に失敗したら 1 件も入らない。
    func addAll(_ newPresets: [Preset]) throws {
        guard !newPresets.isEmpty else { return }
        let updated = newPresets + presets
        try save(updated)
        presets = updated
    }
```

`FolderArt/Services/PresetImporter.swift`:

```swift
import AppKit

enum PresetImporter {
    /// パックをお気に入りに取り込む。重複は「既存 + このパックで追加を決めた項目」に対して判定。
    /// 画像は AssetStore に新しい ID で複製し、保存に失敗したら複製した PNG を消す。
    static func importPack(_ pack: Pack, into store: PresetStore, assets: AssetStore) throws -> ImportSummary {
        var staged: [Preset] = []
        var createdAssets: [UUID] = []
        var skipped = 0

        // 画像プリセットは assetID が違うので、PNG のバイト列で同一性を判定する
        func pngData(of preset: Preset) -> Data? {
            preset.overlay.assetID.flatMap { try? Data(contentsOf: assets.url(for: $0)) }
        }
        func isIdentical(_ entry: PackEntry, _ p: Preset) -> Bool {
            guard p.settings == entry.settings else { return false }
            if let image = entry.image, entry.overlay.assetID != nil {
                return p.overlay.assetID != nil && pngData(of: p) == image
            }
            return p.overlay == entry.overlay
        }

        do {
            for entry in pack.presets {
                if (store.presets + staged).contains(where: { isIdentical(entry, $0) }) {
                    skipped += 1
                    continue
                }
                var overlay = entry.overlay
                if entry.overlay.assetID != nil {
                    guard let data = entry.image, PackReader.isPNG(data), let image = NSImage(data: data) else {
                        throw PackError.invalidImage(entry.name)
                    }
                    let id = try assets.store(image)
                    createdAssets.append(id)
                    overlay = .image(assetID: id)
                }
                let name = PresetStore.defaultName(forProposed: entry.name, existing: store.presets + staged)
                staged.append(Preset(name: name, overlay: overlay, settings: entry.settings))
            }
            try store.addAll(staged)
        } catch {
            for id in createdAssets { try? assets.remove(id) }
            throw error
        }
        return ImportSummary(added: staged.count, skippedIdentical: skipped)
    }
}
```

`PresetStore` に、提案名を起点に「名前 2」を作るヘルパを足す (既存の `defaultName(for:existing:)` は `overlay.displayName` を起点にするので、名前を指定する版が要る):

```swift
    /// proposed をそのまま、重なれば "proposed 2", "proposed 3" … にする
    static func defaultName(forProposed proposed: String, existing: [Preset]) -> String {
        let base = proposed.isEmpty ? String(localized: "お気に入り") : proposed
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
```

既存の `defaultName(for:existing:)` の本体はこのヘルパを呼ぶ形に直す (`defaultName(forProposed: overlay.displayName, existing:)`)。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/PresetStoreTests -only-testing:FolderArtTests/PresetImporterTests`)
Expected: 既存 5 + 新規 2 + 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Stores/PresetStore.swift FolderArt/Services/PresetImporter.swift FolderArtTests/PresetStoreTests.swift FolderArtTests/PresetImporterTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ PresetImporter を追加 (重複の判定、名前の付け直し、一括保存)"
```

---

### Task 6: 書き出し・読み込みの入り口 (メニュー、ファイル関連付け、AppModel)

**Files:**
- Modify: `FolderArt/AppModel.swift` (`exportPack()`, `importPack(url:)`, `packType`)
- Modify: `FolderArt/Views/PresetStripView.swift` (「…」メニュー)
- Modify: `FolderArt/FolderArtApp.swift` (ファイルメニュー → 通知)
- Modify: `FolderArt/ContentView.swift` (`onOpenURL`、通知の受け口)
- Modify: `project.yml` (UTType 宣言)
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Consumes: `PackWriter`, `PackReader`, `PresetImporter`
- Produces:
  - `AppModel`: `static let packType: UTType`, `func exportPack()` (NSSavePanel)、`func exportPack(to url: URL)`、`func importPack(url: URL)`、`static let exportPackNotification = Notification.Name("FolderArt.exportPack")`, `static let importPackNotification = Notification.Name("FolderArt.importPack")`
  - `PresetStripView` に `onExport: () -> Void`, `onImport: () -> Void` を追加

- [ ] **Step 1: テストを書く**

`FolderArtTests/AppModelTests.swift` に追加:

```swift
    func testExportAndImportPackRoundTrip() throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let file = root.appendingPathComponent("test.folderartpack")
        model.exportPack(to: file)
        XCTAssertNil(model.errorMessage)
        XCTAssertTrue(FileManager.default.fileExists(atPath: file.path))

        try model.presets.remove(model.presets.presets[0])
        model.importPack(url: file)
        XCTAssertEqual(model.presets.presets.map(\.name), ["星"])
        XCTAssertEqual(model.errorMessage, String(localized: "1 件のお気に入りを追加しました。"))
    }

    func testImportPackReportsCorruptFile() throws {
        let file = root.appendingPathComponent("bad.folderartpack")
        try "nope".data(using: .utf8)!.write(to: file)
        model.importPack(url: file)
        XCTAssertTrue(model.presets.presets.isEmpty)
        XCTAssertEqual(model.errorMessage, PackError.corrupted.errorDescription)
    }

    func testExportIsIgnoredWhileApplying() throws {
        try model.presets.add(name: "a", overlay: .text("a"), settings: CompositionSettings())
        let file = root.appendingPathComponent("x.folderartpack")
        model.isApplying = true
        model.exportPack(to: file)
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testImportIsIgnoredWhileApplying() throws {
        let file = root.appendingPathComponent("test.folderartpack")
        try PackWriter.write([Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())],
                             assets: model.assets, appVersion: "1.3.0").write(to: file)
        model.isApplying = true
        model.importPack(url: file)
        XCTAssertTrue(model.presets.presets.isEmpty)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: ビルドエラー

- [ ] **Step 3: AppModel を実装**

`FolderArt/AppModel.swift` に追加 (`// MARK: - お気に入り` の中):

```swift
    static let packType = UTType(exportedAs: "com.example.folderart.pack", conformingTo: .json)
    static let exportPackNotification = Notification.Name("FolderArt.exportPack")
    static let importPackNotification = Notification.Name("FolderArt.importPack")

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// お気に入り全部を 1 ファイルに書き出す (NSSavePanel)
    func exportPack() {
        guard !isApplying, !presets.presets.isEmpty else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.packType]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = "FolderArt-お気に入り-\(formatter.string(from: Date())).folderartpack"
        panel.prompt = String(localized: "書き出す")
        if panel.runModal() == .OK, let url = panel.url { exportPack(to: url) }
    }

    func exportPack(to url: URL) {
        guard !isApplying else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try PackWriter.write(presets.presets, assets: assets, appVersion: appVersion)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "パックを書き出せませんでした: \(error.localizedDescription)")
        }
    }

    /// パックを選んで読み込む (NSOpenPanel)
    func importPackWithPanel() {
        guard !isApplying else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.packType, .json]
        panel.prompt = String(localized: "読み込む")
        if panel.runModal() == .OK, let url = panel.url { importPack(url: url) }
    }

    /// パックを読み込んでお気に入りに追加し、結果をアラートで伝える
    func importPack(url: URL) {
        guard !isApplying else { return }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try Data(contentsOf: url)
            let pack = try PackReader.read(data)
            let summary = try PresetImporter.importPack(pack, into: presets, assets: assets)
            errorMessage = summary.skippedIdentical == 0
                ? String(localized: "\(summary.added) 件のお気に入りを追加しました。")
                : String(localized: "\(summary.added) 件のお気に入りを追加しました (\(summary.skippedIdentical) 件は同じものがあるため省略)。")
        } catch let error as PackError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = String(localized: "パックを読み込めません: \(error.localizedDescription)")
        }
    }
```

`errorMessage` は「お知らせ」アラートの文言として流用する (成功の要約もここに載せる。アラートのタイトルは既に「お知らせ」)。

- [ ] **Step 4: メニューと関連付け**

`FolderArt/Views/PresetStripView.swift`: プロパティに `let onExport: () -> Void` と `let onImport: () -> Void` を追加し、★ ボタンの後に:

```swift
            Menu {
                Button("パックを書き出す…") { onExport() }
                    .disabled(store.presets.isEmpty || isApplying)
                Button("パックを読み込む…") { onImport() }
                    .disabled(isApplying)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help(Text("お気に入りのパックを書き出す / 読み込む"))
```

`FolderArt/ContentView.swift`: `PresetStripView(...)` に `onExport: { model.exportPack() }, onImport: { model.importPackWithPanel() }` を追加。`.alert` の前に:

```swift
        .onOpenURL { url in model.importPack(url: url) }
        .onReceive(NotificationCenter.default.publisher(for: AppModel.exportPackNotification)) { _ in model.exportPack() }
        .onReceive(NotificationCenter.default.publisher(for: AppModel.importPackNotification)) { _ in model.importPackWithPanel() }
```

`FolderArt/FolderArtApp.swift`: `Window { ... }` の後に:

```swift
        .commands {
            CommandGroup(after: .importExport) {
                Button("お気に入りのパックを書き出す…") {
                    NotificationCenter.default.post(name: AppModel.exportPackNotification, object: nil)
                }
                Button("お気に入りのパックを読み込む…") {
                    NotificationCenter.default.post(name: AppModel.importPackNotification, object: nil)
                }
            }
        }
```

`project.yml` の `targets.FolderArt.info.properties` に追加:

```yaml
        CFBundleDocumentTypes:
          - CFBundleTypeName: FolderArt Preset Pack
            CFBundleTypeRole: Viewer
            LSHandlerRank: Owner
            LSItemContentTypes: [com.example.folderart.pack]
        UTExportedTypeDeclarations:
          - UTTypeIdentifier: com.example.folderart.pack
            UTTypeDescription: FolderArt Preset Pack
            UTTypeConformsTo: [public.json]
            UTTypeTagSpecification:
              public.filename-extension: [folderartpack]
```

- [ ] **Step 5: テストとビルド**

Run: `xcodegen generate` → `grep -c "folderartpack" FolderArt/Info.plist` が 1 以上 → テスト実行 (全体)
Expected: 全 PASS、警告 0

- [ ] **Step 6: コミット**

```bash
git add FolderArt/AppModel.swift FolderArt/Views/PresetStripView.swift FolderArt/FolderArtApp.swift FolderArt/ContentView.swift project.yml FolderArt/Info.plist FolderArt.xcodeproj/project.pbxproj FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ お気に入りパックの書き出し・読み込み (帯のメニュー、ファイルメニュー、.folderartpack の関連付け)"
```

---

### Task 7: フォルダの同一性 (fileID) と履歴の置き換え

**Files:**
- Create: `FolderArt/Services/FileIdentity.swift`
- Modify: `FolderArt/Models/IconTask.swift` (`fileID`)
- Modify: `FolderArt/Stores/HistoryStore.swift` (`upsert` の判定、`task(forFolderPath:fileID:)`)
- Modify: `FolderArt/Services/ApplyCoordinator.swift` (`fileID` の記録と既存行の検索)
- Modify: `FolderArt/Services/FolderIconManager.swift` (`removeBackup(atBackupPath:)`)
- Test: `FolderArtTests/FileIdentityTests.swift`, `FolderArtTests/HistoryStoreTests.swift`, `FolderArtTests/IconTaskTests.swift`

**Interfaces:**
- Produces:
  - `enum FileIdentity { static func make(for url: URL) -> String? }` — `"<volumeUUID>:<inode>"`、取れなければ nil
  - `IconTask.fileID: String?` (init 引数 `fileID: String? = nil`、`decodeIfPresent`)
  - `HistoryStore.task(forFolderPath:fileID:) -> IconTask?`、`upsert` は path または fileID の一致で置き換え
  - `FolderIconManager.removeBackup(atBackupPath path: String?)` — バックアップ PNG の親ディレクトリ (バックアップディレクトリ配下のときだけ) を削除

- [ ] **Step 1: テストを書く**

`FolderArtTests/FileIdentityTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class FileIdentityTests: XCTestCase {
    func testSameFolderSameIDAndSurvivesRename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileIdentity_\(UUID().uuidString)")
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id1 = try XCTUnwrap(FileIdentity.make(for: a))
        XCTAssertTrue(id1.contains(":"))
        XCTAssertEqual(FileIdentity.make(for: a), id1)

        let b = root.appendingPathComponent("B")
        try FileManager.default.moveItem(at: a, to: b)
        XCTAssertEqual(FileIdentity.make(for: b), id1)           // 同一ボリューム内の改名で不変

        let c = root.appendingPathComponent("C")
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        XCTAssertNotEqual(FileIdentity.make(for: c), id1)
        XCTAssertNil(FileIdentity.make(for: root.appendingPathComponent("missing")))
    }
}
```

`FolderArtTests/HistoryStoreTests.swift` に追加:

```swift
    func testUpsertReplacesRowWithSameFileIDEvenIfPathChanged() throws {
        try store.upsert(IconTask(folderPath: "/old/A", bookmarkData: Data(), backupPath: nil,
                                  overlay: .text("1"), settings: CompositionSettings(), fileID: "vol:1"))
        try store.upsert(IconTask(folderPath: "/new/A", bookmarkData: Data(), backupPath: nil,
                                  overlay: .text("2"), settings: CompositionSettings(), fileID: "vol:1"))
        XCTAssertEqual(store.tasks.count, 1)
        XCTAssertEqual(store.tasks.first?.folderPath, "/new/A")
        XCTAssertEqual(store.task(forFolderPath: "/gone", fileID: "vol:1")?.overlay, .text("2"))
    }

    func testUpsertInheritsBackupPathFromReplacedRow() throws {
        try store.upsert(IconTask(folderPath: "/a", bookmarkData: Data(), backupPath: "/backups/k/original.png",
                                  overlay: .text("1"), settings: CompositionSettings()))
        try store.upsert(makeTask(folderPath: "/a", overlay: .text("2")))   // backupPath nil
        XCTAssertEqual(store.tasks.first?.backupPath, "/backups/k/original.png")
        XCTAssertEqual(store.tasks.first?.overlay, .text("2"))
    }

    func testNilFileIDsNeverMatchEachOther() throws {
        try store.upsert(makeTask(folderPath: "/a"))
        try store.upsert(makeTask(folderPath: "/b"))
        XCTAssertEqual(store.tasks.count, 2)
    }
```

`FolderArtTests/IconTaskTests.swift` に追加:

```swift
    func testFileIDRoundTripsAndDefaultsToNil() throws {
        let task = IconTask(folderPath: "/x", bookmarkData: Data(), backupPath: nil,
                            overlay: .text("1"), settings: CompositionSettings(), fileID: "vol:42")
        let data = try JSONEncoder().encode(task)
        XCTAssertEqual(try JSONDecoder().decode(IconTask.self, from: data).fileID, "vol:42")
        let json = """
        {"version":2,"id":"6E3A0C4E-3F2B-4C4B-9D1B-7B7B4E5D1A11","folderPath":"/x","bookmarkData":"","appliedAt":0,
         "overlay":{"text":{"_0":"1"}},"settings":{}}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(IconTask.self, from: json).fileID)
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/FileIdentityTests -only-testing:FolderArtTests/HistoryStoreTests -only-testing:FolderArtTests/IconTaskTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Services/FileIdentity.swift`:

```swift
import Foundation

/// フォルダの同一性: ボリューム UUID とファイル ID の組。同一ボリューム内の改名・移動で不変。
/// コピーや別ボリュームへの移動、作り直しは別物になる (呼び出し側は path 比較に落ちる)。
enum FileIdentity {
    /// fileResourceIdentifierKey は inode に加えてマウント時に決まるファイルシステム ID を含み、
    /// 再起動をまたぐと変わる (Apple の文書でも "not persistent across system restarts")。
    /// 履歴は起動をまたいで残るので、ボリューム UUID と inode 番号 (systemFileNumber) で作る。
    static func make(for url: URL) -> String? {
        guard let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return "\(volume):\(inode)"
    }
}
```

`FolderArt/Models/IconTask.swift`: `let fileID: String?` を `settings` の後に追加。`backupPath` だけ差し替えたコピーを返す `func withBackupPath(_ path: String?) -> IconTask` を足す (他のフィールドはそのまま、`id` も維持)。`init` に `fileID: String? = nil` を末尾に足して代入。`CodingKeys` に `fileID` を追加。`init(from:)` の両分岐の前 (共通部分) に `fileID = try c.decodeIfPresent(String.self, forKey: .fileID)`。`encode(to:)` に `try c.encodeIfPresent(fileID, forKey: .fileID)`。

`FolderArt/Stores/HistoryStore.swift`:

```swift
    /// 同じ folderPath か、同じ fileID (nil 同士は不一致) の行があれば置き換え、先頭に置く。
    /// 置き換えられる行が backupPath を持ち、新しい行が持たなければ引き継ぐ (元アイコンの記録を失わない)
    func upsert(_ task: IconTask) throws {
        let replaced = tasks.first { Self.sameFolder($0, task) }
        let merged = Self.inheritingBackupPath(task, from: replaced)
        var updated = tasks.filter { !Self.sameFolder($0, merged) }
        updated.insert(merged, at: 0)
        try save(updated)
        tasks = updated
    }

    static func inheritingBackupPath(_ task: IconTask, from replaced: IconTask?) -> IconTask {
        guard task.backupPath == nil, let inherited = replaced?.backupPath else { return task }
        return task.withBackupPath(inherited)
    }

    static func sameFolder(_ a: IconTask, _ b: IconTask) -> Bool {
        if a.folderPath == b.folderPath { return true }
        if let x = a.fileID, let y = b.fileID, x == y { return true }
        return false
    }

    /// path か fileID のどちらかで一致する行
    func task(forFolderPath path: String, fileID: String?) -> IconTask? {
        tasks.first { $0.folderPath == path || (fileID != nil && $0.fileID == fileID) }
    }
```

`task(forFolderPath:)` (1 引数) は残す (既存の呼び出しがある)。

`FolderArt/Services/ApplyCoordinator.swift` の `apply` ループ内: `let fileID = FileIdentity.make(for: folder)` を先頭で取り、`history.task(forFolderPath: ..., fileID: fileID)` で既存行を探し、`IconTask(...)` に `fileID: fileID` を渡す。`reset(_ task:)` の末尾 `iconManager.removeBackup(for: URL(fileURLWithPath: task.folderPath))` を `iconManager.removeBackup(atBackupPath: task.backupPath)` に、`reset(folder:)` の `iconManager.removeBackup(for: folder)` も `iconManager.removeBackup(atBackupPath: task.backupPath)` に変える (行の `backupPath` を正とする)。

`FolderArt/Services/FolderIconManager.swift` に追加:

```swift
    /// 履歴の行が持つ backupPath (…/backups/<key>/original.png) の親ディレクトリを消す。
    /// バックアップディレクトリの外を指していたら何もしない。
    func removeBackup(atBackupPath path: String?) {
        guard let path else { return }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        let root = backupDirectory.standardizedFileURL.pathComponents
        // 文字列の前方一致だと "backups_evil" も通ってしまうので、パス要素単位で包含を見る
        guard dir.pathComponents.count > root.count, Array(dir.pathComponents.prefix(root.count)) == root else { return }
        try? FileManager.default.removeItem(at: dir)
    }
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: 新規 5 件を含め全 PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/FileIdentity.swift FolderArt/Models/IconTask.swift FolderArt/Stores/HistoryStore.swift FolderArt/Services/ApplyCoordinator.swift FolderArt/Services/FolderIconManager.swift FolderArtTests/FileIdentityTests.swift FolderArtTests/HistoryStoreTests.swift FolderArtTests/IconTaskTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ 履歴の同一性をボリューム UUID + ファイル ID で判定し、移動後の二重行を防ぐ"
```

---

### Task 8: 一括適用の履歴書き込みを 1 回に (upsertAll)

**Files:**
- Modify: `FolderArt/Stores/HistoryStore.swift` (`upsertAll`, `saveCount`)
- Modify: `FolderArt/Services/ApplyCoordinator.swift`
- Test: `FolderArtTests/HistoryStoreTests.swift`, `FolderArtTests/ApplyCoordinatorTests.swift`

**Interfaces:**
- Produces:
  - `HistoryStore.upsertAll(_ tasks: [IconTask]) throws` (保存してから反映、失敗時はメモリも不変)、`private(set) var saveCount: Int` (テスト用)
  - `ApplyCoordinator.apply`: フォルダ単位の失敗は部分失敗、成功分は最後に `upsertAll` で 1 回保存。最終保存失敗時はその回に成功した全フォルダを巻き戻して失敗扱い (理由「履歴の保存に失敗」)。

- [ ] **Step 1: テストを書く**

`FolderArtTests/HistoryStoreTests.swift` に追加:

```swift
    func testUpsertAllSavesOnceAndReplacesByFolder() throws {
        try store.upsert(makeTask(folderPath: "/a", overlay: .text("old")))
        let before = store.saveCount
        try store.upsertAll([makeTask(folderPath: "/a", overlay: .text("new")), makeTask(folderPath: "/b")])
        XCTAssertEqual(store.saveCount, before + 1)
        XCTAssertEqual(store.tasks.map(\.folderPath), ["/a", "/b"])
        XCTAssertEqual(store.task(forFolderPath: "/a")?.overlay, .text("new"))
    }

    func testUpsertAllLeavesMemoryUnchangedWhenSaveFails() throws {
        let dir = tempHistoryURL.deletingLastPathComponent().appendingPathComponent("locked_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let s = HistoryStore(storageURL: dir.appendingPathComponent("history.json"))
        try s.upsert(makeTask(folderPath: "/keep"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path) }
        XCTAssertThrowsError(try s.upsertAll([makeTask(folderPath: "/new")]))
        XCTAssertEqual(s.tasks.map(\.folderPath), ["/keep"])
    }
```

`FolderArtTests/ApplyCoordinatorTests.swift` に追加 (既存の `folder(_:)`, `overlayImage`, `coordinator`, `history` を使う):

```swift
    /// 3 フォルダ適用で history.json の書き込みは 1 回
    func testBatchWritesHistoryOnce() async throws {
        let a = try folder("A"), b = try folder("B"), c = try folder("C")
        let before = history.saveCount
        let outcome = await coordinator.apply(overlayImage: overlayImage, overlay: .text("x"),
                                              settings: CompositionSettings(), to: [a, b, c])
        XCTAssertEqual(outcome.succeeded.count, 3)
        XCTAssertEqual(history.saveCount, before + 1)
        XCTAssertEqual(history.tasks.count, 3)
    }

    /// 1 フォルダが無くても残りは成功として 1 回で保存される (部分失敗は従来どおり)
    func testPartialFailureStillSavesTheRest() async throws {
        let a = try folder("A")
        let missing = root.appendingPathComponent("missing")
        let outcome = await coordinator.apply(overlayImage: overlayImage, overlay: .text("x"),
                                              settings: CompositionSettings(), to: [a, missing])
        XCTAssertEqual(outcome.succeeded.map(\.lastPathComponent), ["A"])
        XCTAssertEqual(outcome.failed.map { $0.folder.lastPathComponent }, ["missing"])
        XCTAssertEqual(history.tasks.count, 1)
    }

    /// 最終保存に失敗したら、その回に成功していた全フォルダを巻き戻し、全件失敗として報告
    func testFinalSaveFailureRollsBackEveryAppliedFolder() async throws {
        let a = try folder("A"), b = try folder("B")
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let lockedHistory = HistoryStore(storageURL: locked.appendingPathComponent("history.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let c = ApplyCoordinator(history: lockedHistory, iconManager: FolderIconManager(backupDirectory: root.appendingPathComponent("backups")))

        let outcome = await c.apply(overlayImage: overlayImage, overlay: .text("x"),
                                    settings: CompositionSettings(), to: [a, b])
        XCTAssertTrue(outcome.succeeded.isEmpty)
        XCTAssertEqual(outcome.failed.count, 2)
        XCTAssertTrue(outcome.failed.allSatisfy { $0.reason.contains("履歴の保存に失敗") })
        for f in [a, b] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.appendingPathComponent("Icon\r").path))
        }
        XCTAssertTrue(lockedHistory.tasks.isEmpty)
    }
```

既存の `testHistoryWriteFailureRollsBackIcon` は「1 フォルダで最終保存失敗 → 巻き戻し」として引き続き成立する (期待値は変えない)。

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/HistoryStoreTests -only-testing:FolderArtTests/ApplyCoordinatorTests`)
Expected: ビルドエラー (`upsertAll` / `saveCount` 未定義)

- [ ] **Step 3: HistoryStore を実装**

```swift
    /// 保存した回数 (テスト用)
    private(set) var saveCount = 0

    /// 複数行を一度に反映して保存は 1 回。保存に失敗したらメモリ上の tasks も変えない。
    func upsertAll(_ newTasks: [IconTask]) throws {
        guard !newTasks.isEmpty else { return }
        let merged = newTasks.map { task in Self.inheritingBackupPath(task, from: tasks.first { Self.sameFolder($0, task) }) }
        var updated = tasks.filter { existing in !merged.contains { Self.sameFolder(existing, $0) } }
        updated.insert(contentsOf: merged, at: 0)
        try save(updated)
        tasks = updated
    }
```

`private func save(_:)` の末尾で `saveCount += 1`。

- [ ] **Step 4: ApplyCoordinator を実装**

`apply` のループを次の形に置き換える (`snapshotIcon`, `bookmarkToRecord`, `shouldRemoveFreshBackup`, `FileIdentity` は既存/前タスクのもの):

```swift
        struct Applied {
            let folder: URL
            let task: IconTask
            let previousIcon: NSImage?
            let createdBackup: Bool
        }
        var applied: [Applied] = []
        var failed: [ApplyFailure] = []
        let total = folders.count

        for (index, folder) in folders.enumerated() {
            var backupURL: URL?
            var iconApplied = false
            var createdBackup = false
            let previousIcon = snapshotIcon(of: folder)
            let fileID = FileIdentity.make(for: folder)
            do {
                let existing = history.task(forFolderPath: folder.standardizedFileURL.path, fileID: fileID)
                if let existing {
                    backupURL = existing.backupPath.map { URL(fileURLWithPath: $0) }
                } else {
                    let hadBackup = iconManager.backupExists(for: folder)
                    backupURL = try iconManager.backupCurrentIcon(for: folder)
                    createdBackup = !hadBackup && backupURL != nil
                }
                try iconManager.applyIcon(icon, to: folder)
                iconApplied = true
                let bookmark = Self.bookmarkToRecord(new: try? BookmarkManager.createBookmark(for: folder),
                                                     existing: existing?.bookmarkData)
                let task = IconTask(folderPath: folder.standardizedFileURL.path, bookmarkData: bookmark,
                                    backupPath: backupURL?.path, overlay: overlay, settings: settings, fileID: fileID)
                applied.append(Applied(folder: folder, task: task, previousIcon: previousIcon, createdBackup: createdBackup))
            } catch {
                var reason = error.localizedDescription
                var rollbackSucceeded = true
                if iconApplied {
                    rollbackSucceeded = NSWorkspace.shared.setIcon(previousIcon, forFile: folder.path, options: [])
                    if !rollbackSucceeded { reason += " / 巻き戻し失敗: \(FolderIconError.resetFailed(folder).localizedDescription)" }
                }
                if Self.shouldRemoveFreshBackup(createdBackup: createdBackup, rollbackSucceeded: rollbackSucceeded) {
                    iconManager.removeBackup(for: folder)
                }
                failed.append(ApplyFailure(folder: folder, reason: reason))
            }
            progress(index + 1, total)
            await Task.yield()
        }

        // 履歴は最後に 1 回だけ保存。失敗したら、この回に成功した全フォルダを直前の状態に戻す
        do {
            try history.upsertAll(applied.map(\.task))
        } catch {
            let base = String(localized: "履歴の保存に失敗しました: \(error.localizedDescription)")
            for item in applied {
                var reason = base
                let rollbackSucceeded = NSWorkspace.shared.setIcon(item.previousIcon, forFile: item.folder.path, options: [])
                if !rollbackSucceeded { reason += " / 巻き戻し失敗: \(FolderIconError.resetFailed(item.folder).localizedDescription)" }
                if Self.shouldRemoveFreshBackup(createdBackup: item.createdBackup, rollbackSucceeded: rollbackSucceeded) {
                    iconManager.removeBackup(for: item.folder)
                }
                failed.append(ApplyFailure(folder: item.folder, reason: reason))
            }
            return ApplyOutcome(succeeded: [], failed: failed)
        }
        return ApplyOutcome(succeeded: applied.map(\.folder), failed: failed)
```

`failed` の順序が元のフォルダ順と一致しなくても構わない (アラートは一覧表示)。

- [ ] **Step 5: テスト**

Run: テスト実行 (全体)
Expected: 全 PASS (既存 `testHistoryWriteFailureRollsBackIcon` と `testReapplyReplacesHistoryRow` も緑)

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Stores/HistoryStore.swift FolderArt/Services/ApplyCoordinator.swift FolderArtTests/HistoryStoreTests.swift FolderArtTests/ApplyCoordinatorTests.swift
git commit -m "perf: ⚡️ 一括適用の履歴書き込みを最後の 1 回にし、最終保存失敗時は全件巻き戻す"
```

---

### Task 9: 起動時の掃除 (MaintenanceSweep)

**Files:**
- Create: `FolderArt/Services/MaintenanceSweep.swift`
- Modify: `FolderArt/AppModel.swift` (起動時に 1 回、メインの外で実行)
- Test: `FolderArtTests/MaintenanceSweepTests.swift`

**Interfaces:**
- Produces:
  ```swift
  enum MaintenanceSweep {
      struct Result: Equatable { var backupsRemoved: Int; var corruptFilesRemoved: Int }
      static let corruptFileMaxAge: TimeInterval = 30 * 24 * 60 * 60
      static func run(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                      backupDirectory: URL, appSupportDirectory: URL, now: Date = Date()) -> Result
  }
  ```
  (`referencedBackupPaths` = 履歴の全行の `backupPath`。`historyLoaded == false` のときはバックアップを消さない。)

- [ ] **Step 1: テストを書く**

`FolderArtTests/MaintenanceSweepTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class MaintenanceSweepTests: XCTestCase {
    private var root: URL!
    private var backups: URL!

    override func setUp() {
        super.setUp()
        root = FileManager.default.temporaryDirectory.appendingPathComponent("Sweep_\(UUID().uuidString)")
        backups = root.appendingPathComponent("backups")
        try? FileManager.default.createDirectory(at: backups, withIntermediateDirectories: true)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: root); super.tearDown() }

    private func makeBackup(_ key: String) throws -> String {
        let dir = backups.appendingPathComponent(key)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let png = dir.appendingPathComponent("original.png")
        try Data([1, 2, 3]).write(to: png)
        return png.path
    }

    private func makeCorrupt(_ name: String, ageDays: Double) throws {
        let f = root.appendingPathComponent(name)
        try Data([0]).write(to: f)
        let date = Date().addingTimeInterval(-ageDays * 86400)
        try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: f.path)
    }

    func testRemovesUnreferencedBackupsOnly() throws {
        let kept = try makeBackup("keep")
        _ = try makeBackup("orphan")
        let r = MaintenanceSweep.run(referencedBackupPaths: [kept], historyLoaded: true,
                                     backupDirectory: backups, appSupportDirectory: root)
        XCTAssertEqual(r.backupsRemoved, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: kept))
        XCTAssertFalse(FileManager.default.fileExists(atPath: backups.appendingPathComponent("orphan").path))
    }

    func testKeepsBackupsWhenHistoryFailedToLoad() throws {
        _ = try makeBackup("orphan")
        let r = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: false,
                                     backupDirectory: backups, appSupportDirectory: root)
        XCTAssertEqual(r.backupsRemoved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.appendingPathComponent("orphan").path))
    }

    func testRemovesCorruptFilesOlderThan30Days() throws {
        try makeCorrupt("history.json.corrupt-20260801-000000", ageDays: 31)
        try makeCorrupt("presets.json.corrupt-20260901-000000", ageDays: 29)
        try makeCorrupt("history.json", ageDays: 40)   // 対象外
        let r = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                     backupDirectory: backups, appSupportDirectory: root)
        XCTAssertEqual(r.corruptFilesRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.json.corrupt-20260801-000000").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("presets.json.corrupt-20260901-000000").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.json").path))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/MaintenanceSweepTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Services/MaintenanceSweep.swift`:

```swift
import Foundation

/// 起動時の掃除。失敗は無視する (次回また試す)。
enum MaintenanceSweep {
    struct Result: Equatable {
        var backupsRemoved: Int
        var corruptFilesRemoved: Int
    }

    static let corruptFileMaxAge: TimeInterval = 30 * 24 * 60 * 60

    static func run(referencedBackupPaths: Set<String>, historyLoaded: Bool,
                    backupDirectory: URL, appSupportDirectory: URL, now: Date = Date()) -> Result {
        var result = Result(backupsRemoved: 0, corruptFilesRemoved: 0)
        let fm = FileManager.default

        // 1. どの履歴行からも参照されないバックアップ (履歴が読めていないときは触らない)
        if historyLoaded {
            let referencedDirs = Set(referencedBackupPaths.map { URL(fileURLWithPath: $0).deletingLastPathComponent().standardizedFileURL.path })
            let children = (try? fm.contentsOfDirectory(at: backupDirectory, includingPropertiesForKeys: nil)) ?? []
            for dir in children where !referencedDirs.contains(dir.standardizedFileURL.path) {
                if (try? fm.removeItem(at: dir)) != nil { result.backupsRemoved += 1 }
            }
        }

        // 2. 30 日より古い *.corrupt-* ファイル
        let files = (try? fm.contentsOfDirectory(at: appSupportDirectory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
        for file in files where file.lastPathComponent.contains(".corrupt-") {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? now
            if now.timeIntervalSince(modified) > corruptFileMaxAge, (try? fm.removeItem(at: file)) != nil {
                result.corruptFilesRemoved += 1
            }
        }
        return result
    }
}
```

`FolderArt/AppModel.swift` の `init` 末尾 (`reapAssets()` の後) に:

```swift
        // 起動時の掃除はメインの外で。履歴が読めていない起動ではバックアップを消さない
        let referenced = Set(history.tasks.compactMap(\.backupPath))
        let historyLoaded = history.loadError == nil
        let backups = FolderIconManager.defaultBackupDirectory
        let appSupport = HistoryStore.appSupportDirectory
        Task.detached(priority: .background) {
            _ = MaintenanceSweep.run(referencedBackupPaths: referenced, historyLoaded: historyLoaded,
                                     backupDirectory: backups, appSupportDirectory: appSupport)
        }
```

`FolderIconManager.defaultBackupDirectory` が `static` で存在することを確認する (`init(backupDirectory: URL = FolderIconManager.defaultBackupDirectory)` で参照されている)。テスト用の `AppModel` (一時ディレクトリのストア) でも実行されるが、そのときの `history.tasks` は空で `historyLoaded == true` なので、実機の `~/Library/.../backups` を消してしまう。これを避けるため、`AppModel.init` に `runsMaintenance: Bool = true` を追加し、`AppModelTests` の生成箇所では `runsMaintenance: false` を渡す (既存テストの `AppModel(history:presets:assets:)` 呼び出しをすべて更新)。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: 新規 3 件を含め全 PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/MaintenanceSweep.swift FolderArt/AppModel.swift FolderArtTests/MaintenanceSweepTests.swift FolderArtTests/AppModelTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ 起動時に参照されないバックアップと古い .corrupt-* を掃除する"
```

---

### Task 10: バージョン、README (機能一覧とメイン画像)、最終確認 — コントローラー (親セッション) が実施

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: 1.3.0`, `CURRENT_PROJECT_VERSION: 6`)
- Modify: `README.md` (機能一覧、スクリーンショットの参照先)
- Create: `docs/images/main.png` (実機で撮影。画面収録の権限は親セッションにしかないので、このタスク全体を親セッションが行い、README の参照先変更と画像を同じコミットに入れる)

- [ ] **Step 1: バージョン**

`project.yml`: `MARKETING_VERSION: 1.3.0`、`CURRENT_PROJECT_VERSION: 6`。`xcodegen generate`。

- [ ] **Step 2: README**

機能一覧 (日英併記の箇条書き) に次の 2 行を追加:

- フォルダ名からの自動提案: 記号・絵文字・文字・お気に入りの候補をタブの上に最大 3 つ表示 — Suggestions from the folder name: up to three symbol / emoji / text / preset candidates above the tabs
- お気に入りパック (`.folderartpack`): お気に入りを 1 ファイルで書き出し・読み込み、ダブルクリックで取り込み — Preset packs (`.folderartpack`): export and import all presets as one file; double-click to import

「スクリーンショット」の `<img … src="https://github.com/user-attachments/…">` を次に置き換える:

```html
<img width="760" alt="FolderArt 1.3.0" src="docs/images/main.png" />
```

- [ ] **Step 3: スクリーンショット**

Release ビルドを起動し、フォルダ 3 件 (うち 1 つは「Photos」)、記号タブ、提案の帯にチップ 3 つ、お気に入りのチップ 2 つ、プレビュー表示の状態で `screencapture -x -o -l <CGWindowID>` により Retina 2x で撮り、`docs/images/main.png` に保存してコミットする。

- [ ] **Step 4: 全テストとビルド**

Run: テスト実行 (全体)
Expected: 全 PASS、プロジェクト由来の警告 0

- [ ] **Step 5: コミット**

```bash
git add project.yml FolderArt.xcodeproj/project.pbxproj README.md docs/images/main.png
git commit -m "chore: 🔖 1.3.0 に更新し README の機能一覧とメイン画像を更新"
```

- [ ] **Step 6: 仕上げ (コントローラー)**

実機確認 (提案チップのクリック、「…」メニューからの書き出しと読み込み、`.folderartpack` のダブルクリック、同一名の付け直し、移動したフォルダの再適用で履歴が 1 行のまま) → `docs/images/main.png` の撮影とコミット → Codex CLI で事前レビュー → PR (日英併記) → Codex レビュー対応 → `develop` にマージ → `main` を同期 → v1.3.0 リリース → `/Users/annrie/アプリケーション/FolderArt.app` を入れ替え。
