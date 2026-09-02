# FolderArt 第1段階 実装計画: 供給源4種・お気に入り・一括適用

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** フォルダアイコンに重ねるものを「画像」から「画像 / SF Symbols / 絵文字 / 文字」に広げ、見た目をお気に入りとして保存し、複数フォルダへ一括適用できるようにする。

**Architecture:** 重ねるものを `Overlay` 値型で表し、`OverlayRenderer` が透明正方形画像に描画、`IconComposer` が標準フォルダアイコンと合成する (合成は1回、適用は N 回)。状態は `FolderSelection` / `OverlayState` / `ApplyCoordinator` に分け、`AppModel` が束ねる。保存は `CodableStore<T>` に一本化し、画像は `AssetStore` に 512px PNG として複製する。

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 13.0+, XcodeGen (project.yml が正), XCTest。

**Spec:** `docs/superpowers/specs/2026-09-02-overlay-sources-and-batch-design.md`

## Global Constraints

- deploymentTarget macOS 13.0、SWIFT_VERSION 5.9 (project.yml)。macOS 14 以降専用 API は使わない (`@Observable` 不可、`onChange(of:initial:)` 不可)。
- 新しいファイルを追加したら `xcodegen generate` を実行し、`FolderArt.xcodeproj/project.pbxproj` の差分もコミットに含める。
- テスト実行コマンド (以後「テスト実行」と書いたらこれ):
  ```bash
  xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' -quiet 2>&1 | grep -E "Test Case|error:|failed|Executed|BUILD"
  ```
  1 クラスだけ走らせるときは `-only-testing:FolderArtTests/<ClassName>` を足す。
- 新しい UI 文言は `Text("…")` (自動で `LocalizedStringKey`) か `String(localized: "…")` で書く。`String` 連結で作った文言を `Text` に渡さない。
- SF Symbols の画像ファイルを同梱しない。記号は実行時に `NSImage(systemSymbolName:)` で描く。制限付き記号 (`symbol_restrictions.strings`) はカタログから除外する。
- 新しい依存パッケージは追加しない。
- コミットメッセージは既存の流儀 (`feat: ✨ …`, `fix: 🐛 …`, `refactor: ♻️ …`, `test: ✅ …`, `docs: 📝 …`, `chore: 🔧 …` + 日本語) に合わせ、末尾に次を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_01FJnasAEYf6hgjPTNwdy9EK
  ```
- ブランチは `feature/overlay-sources` (作成済み)。main / develop には直接コミットしない。

## File Structure

```
FolderArt/
├── FolderArtApp.swift                 変更: ウィンドウ 760x720、リサイズ可
├── ContentView.swift                  書き換え: 新ビューの組み立て、ウィンドウ全体ドロップ
├── AppModel.swift                     新規: FolderSelection / OverlayState / ApplyCoordinator / ストアを束ねる glue
├── ContentViewModel.swift             削除 (Task 13 で AppModel に置き換え)
├── Models/
│   ├── IconTask.swift                 変更: v2 形式 + v1 からの移行デコード
│   ├── Overlay.swift                  新規: Overlay 列挙型 + displayName
│   ├── CompositionSettings.swift      新規: IconComposer.swift から移動し、色・フォント欄と Codable を追加
│   ├── CodableColor.swift             新規: RGBA + NSColor 変換、FontWeightValue
│   └── Preset.swift                   新規
├── Services/
│   ├── BitmapCanvas.swift             新規: 透明ビットマップに描画する共通ヘルパ
│   ├── OverlayRenderer.swift          新規: Overlay → 正方形 NSImage
│   ├── IconComposer.swift             変更: 標準フォルダアイコン、compose(overlay:settings:base:)
│   ├── SymbolCatalog.swift            新規: CoreGlyphs 読み込み、制限除外、検索
│   ├── FolderIconManager.swift        変更: setfile 削除、applyIcon を throws に
│   ├── ApplyCoordinator.swift         新規: 一括適用
│   └── BookmarkManager.swift          変更なし
├── Stores/
│   ├── CodableStore.swift             新規
│   ├── HistoryStore.swift             変更: CodableStore 利用、upsert、throws
│   ├── AssetStore.swift               新規
│   └── PresetStore.swift              新規
├── State/
│   ├── FolderSelection.swift          新規
│   └── OverlayState.swift             新規
├── Views/
│   ├── DropZoneView.swift             変更: 複数 URL、DropReceiver を公開して再利用
│   ├── FolderListView.swift           新規
│   ├── OverlayPickerView.swift        新規 (4タブ)
│   ├── SymbolGridView.swift           新規 (記号タブの中身)
│   ├── PresetStripView.swift          新規
│   ├── ControlsView.swift             変更: 色の行、表示名修正
│   ├── PreviewView.swift              新規: hover 拡大 + 実寸列
│   └── HistoryView.swift              変更: v2 表示
└── Resources/
    └── restricted-symbols.txt         新規: fallback 用の制限記号一覧
FolderArtTests/
├── CodableColorTests.swift            新規
├── CompositionSettingsTests.swift     新規
├── OverlayTests.swift                 新規
├── IconTaskTests.swift                変更
├── CodableStoreTests.swift            新規
├── HistoryStoreTests.swift            変更
├── AssetStoreTests.swift              新規
├── PresetStoreTests.swift             新規
├── OverlayRendererTests.swift         新規
├── IconComposerTests.swift            変更
├── SymbolCatalogTests.swift           新規
├── FolderIconManagerTests.swift       変更
├── FolderSelectionTests.swift         新規
├── OverlayStateTests.swift            新規
├── ApplyCoordinatorTests.swift        新規
├── ContentViewModelTests.swift        削除 (Task 13)
└── TestSupport.swift                  新規: テスト用画像生成・ピクセル検査ヘルパ
```

---

### Task 1: CodableColor / FontWeightValue と CompositionSettings の Codable 化

**Files:**
- Create: `FolderArt/Models/CodableColor.swift`
- Create: `FolderArt/Models/CompositionSettings.swift`
- Modify: `FolderArt/Services/IconComposer.swift:1-10` (構造体定義を削除)
- Test: `FolderArtTests/CodableColorTests.swift`, `FolderArtTests/CompositionSettingsTests.swift`

**Interfaces:**
- Produces:
  - `struct CodableColor: Codable, Equatable, Sendable { var red, green, blue, alpha: Double; static let white; init(red:green:blue:alpha:); init(_ color: NSColor); var nsColor: NSColor }`
  - `enum FontWeightValue: String, Codable, CaseIterable, Sendable { regular, medium, semibold, bold, heavy, black; var nsWeight: NSFont.Weight }`
  - `struct CompositionSettings: Codable, Equatable, Sendable` に `tintColor: CodableColor = .white`, `fontName: String? = nil`, `fontWeight: FontWeightValue = .bold` を追加。memberwise init は維持 (既存テストが使う)。

- [ ] **Step 1: テストを書く**

`FolderArtTests/CodableColorTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class CodableColorTests: XCTestCase {

    func testRoundTripThroughJSON() throws {
        let color = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)
        XCTAssertEqual(decoded, color)
    }

    func testConvertsFromAndToNSColor() {
        let original = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let codable = CodableColor(original)
        XCTAssertEqual(codable.red, 1.0, accuracy: 0.001)
        XCTAssertEqual(codable.green, 0.5, accuracy: 0.001)
        XCTAssertEqual(codable.blue, 0.0, accuracy: 0.001)

        let back = codable.nsColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(back.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(back.greenComponent, 0.5, accuracy: 0.001)
    }

    func testFontWeightMapsToNSFontWeight() {
        XCTAssertEqual(FontWeightValue.bold.nsWeight, .bold)
        XCTAssertEqual(FontWeightValue.regular.nsWeight, .regular)
        XCTAssertEqual(FontWeightValue.allCases.count, 6)
    }
}
```

`FolderArtTests/CompositionSettingsTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class CompositionSettingsTests: XCTestCase {

    func testDefaultsIncludeWhiteTintAndBoldFont() {
        let s = CompositionSettings()
        XCTAssertEqual(s.tintColor, .white)
        XCTAssertNil(s.fontName)
        XCTAssertEqual(s.fontWeight, .bold)
    }

    func testRoundTripThroughJSON() throws {
        var s = CompositionSettings(position: .badge, scale: 0.4, opacity: 0.7,
                                    verticalOffset: 0.1, clipToFolderShape: false)
        s.tintColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        s.fontWeight = .heavy
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testDecodingJSONWithoutNewKeysUsesDefaults() throws {
        // 将来キーを足したときの後方互換を保証する
        let json = """
        {"position":"center","scale":0.6,"opacity":0.9,"verticalOffset":0.0,"clipToFolderShape":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: json)
        XCTAssertEqual(decoded.tintColor, .white)
        XCTAssertEqual(decoded.fontWeight, .bold)
        XCTAssertNil(decoded.fontName)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/CodableColorTests`)
Expected: ビルドエラー (`CodableColor` が未定義)

- [ ] **Step 3: 実装**

`FolderArt/Models/CodableColor.swift`:

```swift
import AppKit

/// JSON に保存できる sRGB 色。
struct CodableColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent),
                  blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 文字系オーバーレイの太さ。第1段階では UI に出さず初期値 (.bold) のみ使う。
enum FontWeightValue: String, Codable, CaseIterable, Sendable {
    case regular, medium, semibold, bold, heavy, black

    var nsWeight: NSFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }
}
```

`FolderArt/Models/CompositionSettings.swift` (IconComposer.swift の 4〜10 行目から移動し拡張):

```swift
import Foundation

struct CompositionSettings: Codable, Equatable, Sendable {
    var position: IconPosition = .center
    var scale: Double = 0.6              // 0.2 ... 1.0
    var opacity: Double = 0.9            // 0.1 ... 1.0
    var verticalOffset: Double = 0.0     // -0.4 ... 0.4 (上:正, 下:負)
    var clipToFolderShape: Bool = true   // フォルダー形状に切り抜く
    var tintColor: CodableColor = .white // 記号・文字の色
    var fontName: String? = nil          // nil = システムフォント (rounded)。第3段階で UI 開放
    var fontWeight: FontWeightValue = .bold
}

// memberwise init を残すため、カスタムデコードは extension に置く
extension CompositionSettings {
    private enum CodingKeys: String, CodingKey {
        case position, scale, opacity, verticalOffset, clipToFolderShape, tintColor, fontName, fontWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CompositionSettings()
        position          = try c.decodeIfPresent(IconPosition.self,    forKey: .position)          ?? d.position
        scale             = try c.decodeIfPresent(Double.self,          forKey: .scale)             ?? d.scale
        opacity           = try c.decodeIfPresent(Double.self,          forKey: .opacity)           ?? d.opacity
        verticalOffset    = try c.decodeIfPresent(Double.self,          forKey: .verticalOffset)    ?? d.verticalOffset
        clipToFolderShape = try c.decodeIfPresent(Bool.self,            forKey: .clipToFolderShape) ?? d.clipToFolderShape
        tintColor         = try c.decodeIfPresent(CodableColor.self,    forKey: .tintColor)         ?? d.tintColor
        fontName          = try c.decodeIfPresent(String.self,          forKey: .fontName)
        fontWeight        = try c.decodeIfPresent(FontWeightValue.self, forKey: .fontWeight)        ?? d.fontWeight
    }
}
```

`FolderArt/Services/IconComposer.swift` の 4〜10 行目 (`struct CompositionSettings … }`) を削除する。

- [ ] **Step 4: プロジェクト再生成とテスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/CodableColorTests -only-testing:FolderArtTests/CompositionSettingsTests`)
Expected: 6 tests PASS。全体ビルドも通る。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/CodableColor.swift FolderArt/Models/CompositionSettings.swift FolderArt/Services/IconComposer.swift FolderArtTests/CodableColorTests.swift FolderArtTests/CompositionSettingsTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ CompositionSettings を Codable 化し色・フォント欄を追加"
```

---

### Task 2: Overlay 列挙型と IconTask v2 (v1 からの移行)

**Files:**
- Create: `FolderArt/Models/Overlay.swift`
- Modify: `FolderArt/Models/IconTask.swift`
- Modify: `FolderArt/ContentViewModel.swift:72-82` (IconTask 生成部。暫定対応)
- Modify: `FolderArt/Views/HistoryView.swift:43`
- Test: `FolderArtTests/OverlayTests.swift`, `FolderArtTests/IconTaskTests.swift`

**Interfaces:**
- Produces:
  - `enum Overlay: Codable, Equatable, Hashable, Sendable { case image(assetID: UUID); case symbol(name: String); case emoji(String); case text(String); case legacyImage(name: String) }`
  - `Overlay.displayName: String`, `Overlay.assetID: UUID?`, `Overlay.canReapply: Bool`
  - `struct IconTask` v2: `version, id, folderPath, bookmarkData, appliedAt, backupPath: String?, overlay: Overlay, settings: CompositionSettings`。`init(id:folderPath:bookmarkData:appliedAt:backupPath:overlay:settings:)`
- 暫定: `ContentViewModel` は `overlay: .legacyImage(name:)` で IconTask を作る (Task 13 で削除される)。

- [ ] **Step 1: テストを書く**

`FolderArtTests/OverlayTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class OverlayTests: XCTestCase {

    func testRoundTripAllCases() throws {
        let id = UUID()
        let cases: [Overlay] = [
            .image(assetID: id), .symbol(name: "star.fill"), .emoji("🎵"),
            .text("2026"), .legacyImage(name: "old.png")
        ]
        for overlay in cases {
            let data = try JSONEncoder().encode(overlay)
            let decoded = try JSONDecoder().decode(Overlay.self, from: data)
            XCTAssertEqual(decoded, overlay)
        }
    }

    func testDisplayNameAndFlags() {
        let id = UUID()
        XCTAssertEqual(Overlay.symbol(name: "star.fill").displayName, "star.fill")
        XCTAssertEqual(Overlay.emoji("🎵").displayName, "🎵")
        XCTAssertEqual(Overlay.text("2026").displayName, "2026")
        XCTAssertEqual(Overlay.legacyImage(name: "old.png").displayName, "old.png")
        XCTAssertEqual(Overlay.image(assetID: id).assetID, id)
        XCTAssertNil(Overlay.symbol(name: "x").assetID)
        XCTAssertFalse(Overlay.legacyImage(name: "old.png").canReapply)
        XCTAssertTrue(Overlay.text("a").canReapply)
    }
}
```

`FolderArtTests/IconTaskTests.swift` を丸ごと置き換え:

```swift
import XCTest
@testable import FolderArt

final class IconTaskTests: XCTestCase {

    func testV2RoundTrip() throws {
        let task = IconTask(
            folderPath: "/Users/test/Documents",
            bookmarkData: Data([1, 2, 3]),
            appliedAt: Date(timeIntervalSince1970: 1000),
            backupPath: nil,
            overlay: .symbol(name: "star.fill"),
            settings: CompositionSettings(position: .badge, scale: 0.5, opacity: 0.8)
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(IconTask.self, from: data)
        XCTAssertEqual(decoded, task)
        XCTAssertEqual(decoded.version, IconTask.currentVersion)
    }

    func testV1JSONMigratesToLegacyImage() throws {
        // 1.0.1 が書いていた形式 (version 欄なし、設定が平置き)
        let json = """
        {"id":"6E3A0C4E-3F2B-4C4B-9D1B-7B7B4E5D1A11","folderPath":"/tmp/a",
         "bookmarkData":"","appliedAt":1000,"backupPath":"","imageName":"photo.png",
         "position":"badge","scale":0.5,"opacity":0.8,"verticalOffset":0.1,"clipToFolderShape":false}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(IconTask.self, from: json)
        XCTAssertEqual(task.version, IconTask.currentVersion)
        XCTAssertEqual(task.folderPath, "/tmp/a")
        XCTAssertEqual(task.overlay, .legacyImage(name: "photo.png"))
        XCTAssertNil(task.backupPath)                       // "" は nil に正規化
        XCTAssertEqual(task.settings.position, .badge)
        XCTAssertEqual(task.settings.scale, 0.5)
        XCTAssertEqual(task.settings.verticalOffset, 0.1)
        XCTAssertFalse(task.settings.clipToFolderShape)
        XCTAssertEqual(task.settings.tintColor, .white)     // 新規欄は初期値
    }

    func testIconPositionHasTwoCases() {
        XCTAssertEqual(IconPosition.allCases.count, 2)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/OverlayTests -only-testing:FolderArtTests/IconTaskTests`)
Expected: ビルドエラー (`Overlay` 未定義)

- [ ] **Step 3: 実装**

`FolderArt/Models/Overlay.swift`:

```swift
import Foundation

/// フォルダアイコンに重ねるもの。
enum Overlay: Codable, Equatable, Hashable, Sendable {
    case image(assetID: UUID)       // AssetStore 内の PNG
    case symbol(name: String)       // SF Symbols 名
    case emoji(String)
    case text(String)
    case legacyImage(name: String)  // v1 履歴の移行専用。再適用不可

    /// 履歴やお気に入りに表示する短い名前
    var displayName: String {
        switch self {
        case .image:                   return String(localized: "画像")
        case .symbol(let name):        return name
        case .emoji(let s):            return s
        case .text(let s):             return s
        case .legacyImage(let name):   return name
        }
    }

    var assetID: UUID? {
        if case .image(let id) = self { return id }
        return nil
    }

    var canReapply: Bool {
        if case .legacyImage = self { return false }
        return true
    }
}
```

`FolderArt/Models/IconTask.swift` (IconPosition はそのまま。IconTask を置き換え):

```swift
import Foundation

enum IconPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case center = "center"
    case badge  = "badge"

    var displayName: String {
        switch self {
        case .center: return String(localized: "中央オーバーレイ")
        case .badge:  return String(localized: "右下バッジ")
        }
    }
}

struct IconTask: Codable, Identifiable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let id: UUID
    let folderPath: String
    let bookmarkData: Data
    let appliedAt: Date
    let backupPath: String?
    let overlay: Overlay
    let settings: CompositionSettings

    init(
        id: UUID = UUID(),
        folderPath: String,
        bookmarkData: Data,
        appliedAt: Date = Date(),
        backupPath: String?,
        overlay: Overlay,
        settings: CompositionSettings
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.appliedAt = appliedAt
        self.backupPath = backupPath
        self.overlay = overlay
        self.settings = settings
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, folderPath, bookmarkData, appliedAt, backupPath, overlay, settings
        // v1 only
        case imageName, position, scale, opacity, verticalOffset, clipToFolderShape
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,   forKey: .id)
        folderPath   = try c.decode(String.self, forKey: .folderPath)
        bookmarkData = try c.decode(Data.self,   forKey: .bookmarkData)
        appliedAt    = try c.decode(Date.self,   forKey: .appliedAt)
        let rawBackup = try c.decodeIfPresent(String.self, forKey: .backupPath)
        backupPath   = (rawBackup?.isEmpty ?? true) ? nil : rawBackup
        version      = Self.currentVersion

        if let v = try c.decodeIfPresent(Int.self, forKey: .version), v >= 2 {
            overlay  = try c.decode(Overlay.self, forKey: .overlay)
            settings = try c.decode(CompositionSettings.self, forKey: .settings)
        } else {
            // v1: 平置きの設定と imageName
            let name = try c.decodeIfPresent(String.self, forKey: .imageName) ?? ""
            overlay = .legacyImage(name: name)
            var s = CompositionSettings()
            s.position          = try c.decodeIfPresent(IconPosition.self, forKey: .position) ?? s.position
            s.scale             = try c.decodeIfPresent(Double.self, forKey: .scale) ?? s.scale
            s.opacity           = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? s.opacity
            s.verticalOffset    = try c.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? s.verticalOffset
            s.clipToFolderShape = try c.decodeIfPresent(Bool.self, forKey: .clipToFolderShape) ?? s.clipToFolderShape
            settings = s
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version,      forKey: .version)
        try c.encode(id,           forKey: .id)
        try c.encode(folderPath,   forKey: .folderPath)
        try c.encode(bookmarkData, forKey: .bookmarkData)
        try c.encode(appliedAt,    forKey: .appliedAt)
        try c.encodeIfPresent(backupPath, forKey: .backupPath)
        try c.encode(overlay,      forKey: .overlay)
        try c.encode(settings,     forKey: .settings)
    }
}
```

`FolderArt/ContentViewModel.swift` 72〜82 行目を暫定で置き換え (Task 13 でファイルごと削除):

```swift
            let task = IconTask(
                folderPath: folderURL.path,
                bookmarkData: bookmarkData,
                backupPath: backupURL?.path,
                overlay: .legacyImage(name: imageName.isEmpty ? "カスタム画像" : imageName),
                settings: settings
            )
```

同ファイル 107 行目と 126 行目の `$0.backupPath.isEmpty ? nil : URL(fileURLWithPath: $0.backupPath)` を `$0.backupPath.map { URL(fileURLWithPath: $0) }` (126 行目は `task.backupPath.map { URL(fileURLWithPath: $0) }`) に変える。

`FolderArt/Views/HistoryView.swift` 43 行目:

```swift
                                Text("\(task.overlay.displayName) · \(task.settings.position.displayName)")
```

`FolderArtTests/HistoryStoreTests.swift` の `makeTask` を新 init に合わせる (Task 3 で再度書き換えるが、ここでビルドを通す):

```swift
    private func makeTask(folderPath: String = "/test/folder") -> IconTask {
        IconTask(folderPath: folderPath, bookmarkData: Data(), backupPath: "/backup/original.png",
                 overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
    }
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: 新規 5 tests PASS。既存テストも PASS (FolderIconManagerTests.testBackupReturnsPath は既知の失敗。Task 9 で直す)。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/Overlay.swift FolderArt/Models/IconTask.swift FolderArt/ContentViewModel.swift FolderArt/Views/HistoryView.swift FolderArtTests/OverlayTests.swift FolderArtTests/IconTaskTests.swift FolderArtTests/HistoryStoreTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ Overlay 型を追加し IconTask を v2 形式に移行"
```

---

### Task 3: CodableStore と HistoryStore の刷新 (upsert・エラー伝播)

**Files:**
- Create: `FolderArt/Stores/CodableStore.swift`
- Modify: `FolderArt/Stores/HistoryStore.swift`
- Modify: `FolderArt/ContentViewModel.swift:83,110,131` (`add` → `try upsert`, `remove` → `try? remove`)
- Test: `FolderArtTests/CodableStoreTests.swift`, `FolderArtTests/HistoryStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct CodableStore<T: Codable> { let fileURL: URL; func load() throws -> T?; func save(_ value: T) throws }`
  - `HistoryStore`: `init(storageURL:)`, `convenience init()`, `private(set) var loadError: Error?`, `func upsert(_ task: IconTask) throws`, `func remove(_ task: IconTask) throws`, `func task(forFolderPath: String) -> IconTask?`, `var referencedAssetIDs: Set<UUID>`
  - `static var HistoryStore.appSupportDirectory: URL` (他ストアも使う)

- [ ] **Step 1: テストを書く**

`FolderArtTests/CodableStoreTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class CodableStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodableStoreTests_\(UUID().uuidString)/nested/data.json")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent())
        super.tearDown()
    }

    func testLoadReturnsNilWhenFileMissing() throws {
        let store = CodableStore<[String]>(fileURL: url)
        XCTAssertNil(try store.load())
    }

    func testSaveCreatesDirectoriesAndRoundTrips() throws {
        let store = CodableStore<[String]>(fileURL: url)
        try store.save(["a", "b"])
        XCTAssertEqual(try store.load(), ["a", "b"])
    }

    func testCorruptFileThrows() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        let store = CodableStore<[String]>(fileURL: url)
        XCTAssertThrowsError(try store.load())
    }
}
```

`FolderArtTests/HistoryStoreTests.swift` を丸ごと置き換え:

```swift
import XCTest
@testable import FolderArt

final class HistoryStoreTests: XCTestCase {

    private var tempHistoryURL: URL!
    private var store: HistoryStore!

    override func setUp() {
        super.setUp()
        tempHistoryURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("history_test_\(UUID().uuidString).json")
        store = HistoryStore(storageURL: tempHistoryURL)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: tempHistoryURL)
        super.tearDown()
    }

    private func makeTask(folderPath: String = "/test/folder",
                          overlay: Overlay = .symbol(name: "star.fill")) -> IconTask {
        IconTask(folderPath: folderPath, bookmarkData: Data(), backupPath: nil,
                 overlay: overlay, settings: CompositionSettings())
    }

    func testUpsertIncreasesCount() throws {
        XCTAssertEqual(store.tasks.count, 0)
        try store.upsert(makeTask())
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testNewestTaskIsFirst() throws {
        try store.upsert(makeTask(folderPath: "/folder/A"))
        try store.upsert(makeTask(folderPath: "/folder/B"))
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/B")
    }

    func testUpsertReplacesSameFolder() throws {
        try store.upsert(makeTask(folderPath: "/folder/A", overlay: .text("1")))
        try store.upsert(makeTask(folderPath: "/folder/B"))
        try store.upsert(makeTask(folderPath: "/folder/A", overlay: .text("2")))
        XCTAssertEqual(store.tasks.count, 2)
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/A")
        XCTAssertEqual(store.tasks.first?.overlay, .text("2"))
        XCTAssertEqual(store.task(forFolderPath: "/folder/A")?.overlay, .text("2"))
    }

    func testRemoveTaskDecreasesCount() throws {
        let task = makeTask()
        try store.upsert(task)
        try store.remove(task)
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testPersistenceAcrossInstances() throws {
        let task = makeTask()
        try store.upsert(task)
        let store2 = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertEqual(store2.tasks.count, 1)
        XCTAssertEqual(store2.tasks.first?.folderPath, task.folderPath)
        XCTAssertNil(store2.loadError)
    }

    func testCorruptFileSetsLoadErrorAndStartsEmpty() throws {
        try "broken".data(using: .utf8)!.write(to: tempHistoryURL)
        let s = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertNotNil(s.loadError)
        XCTAssertTrue(s.tasks.isEmpty)
    }

    func testReferencedAssetIDs() throws {
        let id = UUID()
        try store.upsert(makeTask(folderPath: "/a", overlay: .image(assetID: id)))
        try store.upsert(makeTask(folderPath: "/b", overlay: .text("x")))
        XCTAssertEqual(store.referencedAssetIDs, [id])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/CodableStoreTests -only-testing:FolderArtTests/HistoryStoreTests`)
Expected: ビルドエラー (`CodableStore` 未定義、`upsert` 未定義)

- [ ] **Step 3: 実装**

`FolderArt/Stores/CodableStore.swift`:

```swift
import Foundation

/// 1 つの JSON ファイルに 1 つの Codable 値を読み書きする。失敗は throws で返す。
struct CodableStore<T: Codable> {
    let fileURL: URL

    /// ファイルが無ければ nil。壊れていれば throw。
    func load() throws -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func save(_ value: T) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: fileURL, options: .atomic)
    }
}
```

`FolderArt/Stores/HistoryStore.swift`:

```swift
import Foundation
import Combine

final class HistoryStore: ObservableObject {
    @Published private(set) var tasks: [IconTask] = []
    /// 起動時の読み込みに失敗した場合のエラー (UI がアラートに出す)
    private(set) var loadError: Error?

    private let store: CodableStore<[IconTask]>

    /// ~/Library/Application Support/FolderArt
    static var appSupportDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("FolderArt")
    }

    convenience init() {
        self.init(storageURL: Self.appSupportDirectory.appendingPathComponent("history.json"))
    }

    init(storageURL: URL) {
        store = CodableStore(fileURL: storageURL)
        do {
            tasks = try store.load() ?? []
            // v1 から移行した行があれば v2 形式で保存し直す
            if !tasks.isEmpty { try? store.save(tasks) }
        } catch {
            loadError = error
            tasks = []
        }
    }

    /// 同じ folderPath の行があれば置き換え、先頭に置く
    func upsert(_ task: IconTask) throws {
        var updated = tasks.filter { $0.folderPath != task.folderPath }
        updated.insert(task, at: 0)
        try store.save(updated)
        tasks = updated
    }

    func remove(_ task: IconTask) throws {
        let updated = tasks.filter { $0.id != task.id }
        try store.save(updated)
        tasks = updated
    }

    func task(forFolderPath path: String) -> IconTask? {
        tasks.first { $0.folderPath == path }
    }

    var referencedAssetIDs: Set<UUID> {
        Set(tasks.compactMap { $0.overlay.assetID })
    }
}
```

`FolderArt/ContentViewModel.swift` (暫定): 83 行目 `historyStore.add(task)` → `try historyStore.upsert(task)`。110 行目 `if let task { historyStore.remove(task) }` → `if let task { try? historyStore.remove(task) }`。131 行目 `historyStore.remove(task)` → `try? historyStore.remove(task)`。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: CodableStoreTests 3、HistoryStoreTests 7 PASS。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Stores/CodableStore.swift FolderArt/Stores/HistoryStore.swift FolderArt/ContentViewModel.swift FolderArtTests/CodableStoreTests.swift FolderArtTests/HistoryStoreTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "refactor: ♻️ JSON 保存を CodableStore に集約し履歴を upsert 化"
```

---

### Task 4: AssetStore (画像の複製と回収)

**Files:**
- Create: `FolderArt/Stores/AssetStore.swift`
- Create: `FolderArtTests/TestSupport.swift`
- Test: `FolderArtTests/AssetStoreTests.swift`

**Interfaces:**
- Produces:
  - `final class AssetStore { let directory: URL; static let maxSide: CGFloat = 512; convenience init(); init(directory: URL); func store(_ image: NSImage) throws -> UUID; func store(contentsOf url: URL) throws -> UUID; func image(for id: UUID) -> NSImage?; func url(for id: UUID) -> URL; func remove(_ id: UUID) throws; func allIDs() -> Set<UUID>; @discardableResult func reap(keeping referenced: Set<UUID>) throws -> Int }`
  - `enum AssetStoreError: LocalizedError { case unreadableImage(URL), encodingFailed }`
  - テスト補助 `TestSupport.makeSolidImage(size:color:)`, `TestSupport.pixelSize(of:)`, `TestSupport.contains(color:in:tolerance:)`

- [ ] **Step 1: テスト補助とテストを書く**

`FolderArtTests/TestSupport.swift`:

```swift
import AppKit
@testable import FolderArt

enum TestSupport {
    /// 単色のビットマップ画像 (pixel == point)
    static func makeSolidImage(size: CGSize, color: NSColor) -> NSImage {
        BitmapCanvas.draw(size: size) { _ in
            color.setFill()
            NSRect(origin: .zero, size: size).fill()
        }!
    }

    static func bitmap(of image: NSImage) -> NSBitmapImageRep {
        if let rep = image.representations.compactMap({ $0 as? NSBitmapImageRep }).first { return rep }
        return NSBitmapImageRep(data: image.tiffRepresentation!)!
    }

    /// 最初のビットマップ表現のピクセル寸法
    static func pixelSize(of image: NSImage) -> CGSize {
        let rep = bitmap(of: image)
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    /// 画像中に指定色 (sRGB, 許容誤差付き) のピクセルがあるか。4px 刻みで走査。
    static func contains(color target: NSColor, in image: NSImage, tolerance: CGFloat = 0.08) -> Bool {
        let rep = bitmap(of: image)
        let t = target.usingColorSpace(.sRGB)!
        for y in stride(from: 0, to: rep.pixelsHigh, by: 4) {
            for x in stride(from: 0, to: rep.pixelsWide, by: 4) {
                guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB), c.alphaComponent > 0.9 else { continue }
                if abs(c.redComponent - t.redComponent) < tolerance,
                   abs(c.greenComponent - t.greenComponent) < tolerance,
                   abs(c.blueComponent - t.blueComponent) < tolerance { return true }
            }
        }
        return false
    }

    static func pngData(_ image: NSImage) -> Data {
        bitmap(of: image).representation(using: .png, properties: [:])!
    }
}
```

`BitmapCanvas` は Task 6 で作るが、AssetStore もリサイズに使うので **この Task で先に作る** (Step 3 参照)。

`FolderArtTests/AssetStoreTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class AssetStoreTests: XCTestCase {
    private var dir: URL!
    private var store: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AssetStoreTests_\(UUID().uuidString)")
        store = AssetStore(directory: dir)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testStoreWritesPNGAndReadsBack() throws {
        let image = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 60), color: .red)
        let id = try store.store(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: id).path))
        let loaded = try XCTUnwrap(store.image(for: id))
        XCTAssertEqual(TestSupport.pixelSize(of: loaded), CGSize(width: 100, height: 60))
        XCTAssertTrue(TestSupport.contains(color: .red, in: loaded))
    }

    func testLargeImageIsDownscaledTo512() throws {
        let image = TestSupport.makeSolidImage(size: CGSize(width: 2048, height: 1024), color: .blue)
        let id = try store.store(image)
        let loaded = try XCTUnwrap(store.image(for: id))
        XCTAssertEqual(TestSupport.pixelSize(of: loaded), CGSize(width: 512, height: 256))
    }

    func testStoreFromFileURL() throws {
        let src = dir.appendingPathComponent("src.png")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 10, height: 10), color: .green)).write(to: src)
        let id = try store.store(contentsOf: src)
        XCTAssertNotNil(store.image(for: id))
        XCTAssertThrowsError(try store.store(contentsOf: dir.appendingPathComponent("missing.png")))
    }

    func testRemoveAndReap() throws {
        let a = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        let b = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        let c = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        XCTAssertEqual(store.allIDs(), [a, b, c])
        try store.remove(a)
        XCTAssertEqual(store.allIDs(), [b, c])
        let removed = try store.reap(keeping: [b])
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.allIDs(), [b])
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/AssetStoreTests`)
Expected: ビルドエラー (`AssetStore`, `BitmapCanvas` 未定義)

- [ ] **Step 3: 実装**

`FolderArt/Services/BitmapCanvas.swift`:

```swift
import AppKit

/// 透明な RGBA ビットマップに描画して NSImage を返す共通ヘルパ。
/// 出力の pixel 寸法は size と一致する (Retina 倍率の影響を受けない)。
enum BitmapCanvas {
    static func draw(size: CGSize, _ body: (CGSize) -> Void) -> NSImage? {
        guard size.width >= 1, size.height >= 1,
              let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil,
                pixelsWide: Int(size.width.rounded()),
                pixelsHigh: Int(size.height.rounded()),
                bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                colorSpaceName: .calibratedRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let ctx = NSGraphicsContext(bitmapImageRep: rep)
        else { return nil }
        rep.size = size

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        body(size)
        ctx.flushGraphics()
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: size)
        image.addRepresentation(rep)
        return image
    }
}
```

`FolderArt/Stores/AssetStore.swift`:

```swift
import AppKit

enum AssetStoreError: LocalizedError {
    case unreadableImage(URL)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return String(localized: "画像を読み込めません: \(url.lastPathComponent)")
        case .encodingFailed:           return String(localized: "画像の保存に失敗しました")
        }
    }
}

/// オーバーレイ画像を 512px 以下の PNG としてアプリ領域に複製して保持する。
final class AssetStore {
    let directory: URL
    static let maxSide: CGFloat = 512

    convenience init() {
        self.init(directory: HistoryStore.appSupportDirectory.appendingPathComponent("assets"))
    }

    init(directory: URL) {
        self.directory = directory
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    func store(contentsOf sourceURL: URL) throws -> UUID {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw AssetStoreError.unreadableImage(sourceURL)
        }
        return try store(image)
    }

    func store(_ image: NSImage) throws -> UUID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resized = Self.downscaled(image, maxSide: Self.maxSide)
        guard let rep = resized.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let png = rep.representation(using: .png, properties: [:]) else {
            throw AssetStoreError.encodingFailed
        }
        let id = UUID()
        try png.write(to: url(for: id), options: .atomic)
        return id
    }

    func image(for id: UUID) -> NSImage? {
        NSImage(contentsOf: url(for: id))
    }

    func remove(_ id: UUID) throws {
        let target = url(for: id)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    func allIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { name in
            name.hasSuffix(".png") ? UUID(uuidString: String(name.dropLast(4))) : nil
        })
    }

    /// 参照されていない PNG を削除し、削除数を返す
    @discardableResult
    func reap(keeping referenced: Set<UUID>) throws -> Int {
        var count = 0
        for id in allIDs().subtracting(referenced) {
            try remove(id)
            count += 1
        }
        return count
    }

    /// 長辺が maxSide を超えていれば縮小し、常に単一ビットマップ表現の画像を返す
    static func downscaled(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let pixel = pixelSize(of: image)
        let ratio = min(1, maxSide / max(pixel.width, pixel.height))
        let target = CGSize(width: (pixel.width * ratio).rounded(), height: (pixel.height * ratio).rounded())
        return BitmapCanvas.draw(size: target) { size in
            image.draw(in: NSRect(origin: .zero, size: size),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver, fraction: 1)
        } ?? image
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/AssetStoreTests`)
Expected: 4 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/BitmapCanvas.swift FolderArt/Stores/AssetStore.swift FolderArtTests/TestSupport.swift FolderArtTests/AssetStoreTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ AssetStore と BitmapCanvas を追加 (画像を 512px PNG で複製)"
```

---

### Task 5: Preset と PresetStore

**Files:**
- Create: `FolderArt/Models/Preset.swift`
- Create: `FolderArt/Stores/PresetStore.swift`
- Test: `FolderArtTests/PresetStoreTests.swift`

**Interfaces:**
- Produces:
  - `struct Preset: Codable, Identifiable, Equatable, Sendable { let id: UUID; var name: String; var overlay: Overlay; var settings: CompositionSettings; let createdAt: Date }`
  - `final class PresetStore: ObservableObject { @Published private(set) var presets: [Preset]; private(set) var loadError: Error?; convenience init(); init(storageURL: URL); @discardableResult func add(name: String?, overlay: Overlay, settings: CompositionSettings) throws -> Preset; func rename(_ preset: Preset, to name: String) throws; func remove(_ preset: Preset) throws; var referencedAssetIDs: Set<UUID>; static func defaultName(for overlay: Overlay, existing: [Preset]) -> String }`
- 画像プリセットは、画像選択時に既に `AssetStore` に複製済みの `assetID` をそのまま参照する。PNG の寿命は `AssetStore.reap(keeping: history ∪ presets ∪ 現在選択)` で管理する (Task 13)。

- [ ] **Step 1: テストを書く**

`FolderArtTests/PresetStoreTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class PresetStoreTests: XCTestCase {
    private var url: URL!
    private var store: PresetStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("presets_\(UUID().uuidString).json")
        store = PresetStore(storageURL: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testAddPersistsAndOrdersNewestFirst() throws {
        try store.add(name: "one", overlay: .text("1"), settings: CompositionSettings())
        try store.add(name: "two", overlay: .text("2"), settings: CompositionSettings())
        XCTAssertEqual(store.presets.map(\.name), ["two", "one"])
        let reloaded = PresetStore(storageURL: url)
        XCTAssertEqual(reloaded.presets.map(\.name), ["two", "one"])
    }

    func testAddWithoutNameUsesDefaultName() throws {
        let p = try store.add(name: nil, overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        XCTAssertEqual(p.name, "star.fill")
        let p2 = try store.add(name: nil, overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        XCTAssertEqual(p2.name, "star.fill 2")
    }

    func testRenameAndRemove() throws {
        let p = try store.add(name: "a", overlay: .emoji("🎵"), settings: CompositionSettings())
        try store.rename(p, to: "music")
        XCTAssertEqual(store.presets.first?.name, "music")
        try store.remove(p)
        XCTAssertTrue(store.presets.isEmpty)
    }

    func testReferencedAssetIDs() throws {
        let id = UUID()
        try store.add(name: "img", overlay: .image(assetID: id), settings: CompositionSettings())
        try store.add(name: "txt", overlay: .text("x"), settings: CompositionSettings())
        XCTAssertEqual(store.referencedAssetIDs, [id])
    }

    func testCorruptFileSetsLoadError() throws {
        try "oops".data(using: .utf8)!.write(to: url)
        let s = PresetStore(storageURL: url)
        XCTAssertNotNil(s.loadError)
        XCTAssertTrue(s.presets.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/PresetStoreTests`)
Expected: ビルドエラー (`PresetStore` 未定義)

- [ ] **Step 3: 実装**

`FolderArt/Models/Preset.swift`:

```swift
import Foundation

/// お気に入り = オーバーレイ + 合成設定 (見た目まるごと)
struct Preset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var overlay: Overlay
    var settings: CompositionSettings
    let createdAt: Date

    init(id: UUID = UUID(), name: String, overlay: Overlay,
         settings: CompositionSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.overlay = overlay
        self.settings = settings
        self.createdAt = createdAt
    }
}
```

`FolderArt/Stores/PresetStore.swift`:

```swift
import Foundation
import Combine

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []
    private(set) var loadError: Error?

    private let store: CodableStore<[Preset]>

    convenience init() {
        self.init(storageURL: HistoryStore.appSupportDirectory.appendingPathComponent("presets.json"))
    }

    init(storageURL: URL) {
        store = CodableStore(fileURL: storageURL)
        do {
            presets = try store.load() ?? []
        } catch {
            loadError = error
            presets = []
        }
    }

    @discardableResult
    func add(name: String?, overlay: Overlay, settings: CompositionSettings) throws -> Preset {
        let resolvedName = (name?.isEmpty == false) ? name! : Self.defaultName(for: overlay, existing: presets)
        let preset = Preset(name: resolvedName, overlay: overlay, settings: settings)
        var updated = presets
        updated.insert(preset, at: 0)
        try store.save(updated)
        presets = updated
        return preset
    }

    func rename(_ preset: Preset, to name: String) throws {
        var updated = presets
        guard let i = updated.firstIndex(where: { $0.id == preset.id }) else { return }
        updated[i].name = name
        try store.save(updated)
        presets = updated
    }

    func remove(_ preset: Preset) throws {
        let updated = presets.filter { $0.id != preset.id }
        try store.save(updated)
        presets = updated
    }

    var referencedAssetIDs: Set<UUID> {
        Set(presets.compactMap { $0.overlay.assetID })
    }

    /// "star.fill", "star.fill 2", "star.fill 3" … と重複しない名前を作る
    static func defaultName(for overlay: Overlay, existing: [Preset]) -> String {
        let base = overlay.displayName.isEmpty ? String(localized: "お気に入り") : overlay.displayName
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/PresetStoreTests`)
Expected: 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/Preset.swift FolderArt/Stores/PresetStore.swift FolderArtTests/PresetStoreTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ お気に入り (Preset / PresetStore) を追加"
```

---

### Task 6: OverlayRenderer (Overlay → 正方形画像)

**Files:**
- Create: `FolderArt/Services/OverlayRenderer.swift`
- Test: `FolderArtTests/OverlayRendererTests.swift`

**Interfaces:**
- Consumes: `BitmapCanvas.draw`, `AssetStore.image(for:)`, `CompositionSettings.tintColor/fontName/fontWeight`
- Produces: `enum OverlayRenderer { static func render(_ overlay: Overlay, settings: CompositionSettings, side: CGFloat, assets: AssetStore) -> NSImage? }`。出力は `side x side` の透明背景ビットマップ。`.emoji("")` / `.text("")` / 空白のみ / `.legacyImage` / 存在しない画像・記号は nil。

- [ ] **Step 1: テストを書く**

`FolderArtTests/OverlayRendererTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class OverlayRendererTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("RendererTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    private func render(_ overlay: Overlay, settings: CompositionSettings = CompositionSettings()) -> NSImage? {
        OverlayRenderer.render(overlay, settings: settings, side: 256, assets: assets)
    }

    func testEachKindRendersSquare() throws {
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        for overlay in [Overlay.image(assetID: id), .symbol(name: "star.fill"), .emoji("🎵"), .text("2026")] {
            let image = try XCTUnwrap(render(overlay), "\(overlay)")
            XCTAssertEqual(TestSupport.pixelSize(of: image), CGSize(width: 256, height: 256), "\(overlay)")
        }
    }

    func testEmptyTextAndEmojiReturnNil() {
        XCTAssertNil(render(.text("")))
        XCTAssertNil(render(.text("   ")))
        XCTAssertNil(render(.emoji("")))
        XCTAssertNil(render(.legacyImage(name: "old.png")))
        XCTAssertNil(render(.image(assetID: UUID())))
        XCTAssertNil(render(.symbol(name: "this.symbol.does.not.exist.zzz")))
    }

    func testSymbolAndTextUseTintColor() {
        var settings = CompositionSettings()
        settings.tintColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let symbol = render(.symbol(name: "square.fill"), settings: settings)!
        XCTAssertTrue(TestSupport.contains(color: .red, in: symbol))
        let text = render(.text("I"), settings: settings)!
        XCTAssertTrue(TestSupport.contains(color: .red, in: text))
    }

    func testImageKeepsAspectInsideSquare() throws {
        // 300x100 の赤い画像 → 256x256 の中で上下に透明帯ができる
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 300, height: 100), color: .red))
        let image = render(.image(assetID: id))!
        let rep = TestSupport.bitmap(of: image)
        XCTAssertEqual(rep.colorAt(x: 128, y: 128)!.alphaComponent, 1.0, accuracy: 0.01) // 中央は不透明
        XCTAssertEqual(rep.colorAt(x: 128, y: 4)!.alphaComponent, 0.0, accuracy: 0.01)   // 上端は透明
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/OverlayRendererTests`)
Expected: ビルドエラー (`OverlayRenderer` 未定義)

- [ ] **Step 3: 実装**

`FolderArt/Services/OverlayRenderer.swift`:

```swift
import AppKit

/// Overlay を透明背景の正方形画像に描く。合成 (IconComposer) はこの出力だけを扱う。
enum OverlayRenderer {

    static func render(_ overlay: Overlay, settings: CompositionSettings,
                       side: CGFloat, assets: AssetStore) -> NSImage? {
        switch overlay {
        case .image(let id):
            guard let image = assets.image(for: id) else { return nil }
            return fitIntoSquare(image, side: side)

        case .symbol(let name):
            guard let symbol = symbolImage(name: name, side: side, settings: settings) else { return nil }
            return fitIntoSquare(symbol, side: side, tint: settings.tintColor.nsColor)

        case .emoji(let s):
            return renderString(s, side: side, settings: settings, applyTint: false)

        case .text(let s):
            return renderString(s, side: side, settings: settings, applyTint: true)

        case .legacyImage:
            return nil
        }
    }

    // MARK: - Private

    /// アスペクト維持で正方形の中央に収める。tint があれば不透明部分をその色で塗る (sourceAtop)。
    private static func fitIntoSquare(_ image: NSImage, side: CGFloat, tint: NSColor? = nil) -> NSImage? {
        let size = image.size
        guard size.width > 0, size.height > 0 else { return nil }
        let ratio = min(side / size.width, side / size.height)
        let drawSize = CGSize(width: size.width * ratio, height: size.height * ratio)
        let origin = CGPoint(x: (side - drawSize.width) / 2, y: (side - drawSize.height) / 2)
        return BitmapCanvas.draw(size: CGSize(width: side, height: side)) { canvas in
            image.draw(in: NSRect(origin: origin, size: drawSize),
                       from: NSRect(origin: .zero, size: size),
                       operation: .sourceOver, fraction: 1)
            if let tint {
                // テンプレート画像 (SF Symbols) は黒で描かれるので、アルファを保ったまま色を乗せる
                tint.setFill()
                NSRect(origin: .zero, size: canvas).fill(using: .sourceAtop)
            }
        }
    }

    private static func symbolImage(name: String, side: CGFloat, settings: CompositionSettings) -> NSImage? {
        guard let base = NSImage(systemSymbolName: name, accessibilityDescription: nil) else { return nil }
        let config = NSImage.SymbolConfiguration(pointSize: side * 0.8, weight: settings.fontWeight.nsWeight)
        guard let configured = base.withSymbolConfiguration(config) else { return nil }
        configured.isTemplate = false
        return configured
    }

    private static func renderString(_ raw: String, side: CGFloat,
                                     settings: CompositionSettings, applyTint: Bool) -> NSImage? {
        let string = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !string.isEmpty else { return nil }

        let maxWidth = side * 0.9
        var fontSize = side * 0.8
        var attributed = attributedString(string, fontSize: fontSize, settings: settings, applyTint: applyTint)
        var bounds = attributed.size()
        // 幅がはみ出す場合は縮小して収める
        if bounds.width > maxWidth {
            fontSize *= maxWidth / bounds.width
            attributed = attributedString(string, fontSize: fontSize, settings: settings, applyTint: applyTint)
            bounds = attributed.size()
        }

        return BitmapCanvas.draw(size: CGSize(width: side, height: side)) { _ in
            let origin = CGPoint(x: (side - bounds.width) / 2, y: (side - bounds.height) / 2)
            attributed.draw(at: origin)
        }
    }

    private static func attributedString(_ string: String, fontSize: CGFloat,
                                         settings: CompositionSettings, applyTint: Bool) -> NSAttributedString {
        let font = makeFont(size: fontSize, settings: settings)
        var attrs: [NSAttributedString.Key: Any] = [.font: font]
        if applyTint { attrs[.foregroundColor] = settings.tintColor.nsColor }
        return NSAttributedString(string: string, attributes: attrs)
    }

    /// fontName が nil ならシステムフォントの rounded デザイン
    static func makeFont(size: CGFloat, settings: CompositionSettings) -> NSFont {
        if let name = settings.fontName, let custom = NSFont(name: name, size: size) {
            return custom
        }
        let system = NSFont.systemFont(ofSize: size, weight: settings.fontWeight.nsWeight)
        if let rounded = system.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: size) {
            return font
        }
        return system
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/OverlayRendererTests`)
Expected: 4 tests PASS。`testImageKeepsAspectInsideSquare` の座標は `colorAt(x:y:)` が左上原点である前提 (NSBitmapImageRep は上端が y=0)。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/OverlayRenderer.swift FolderArtTests/OverlayRendererTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ OverlayRenderer を追加 (画像・記号・絵文字・文字を正方形に描画)"
```

---

### Task 7: IconComposer を標準フォルダアイコン + Overlay 画像入力に変更

**Files:**
- Modify: `FolderArt/Services/IconComposer.swift`
- Modify: `FolderArt/ContentViewModel.swift:34-45` (暫定: 呼び出し側)
- Test: `FolderArtTests/IconComposerTests.swift`

**Interfaces:**
- Produces:
  - `enum IconComposer { static let iconSize: CGSize; static let standardFolderIcon: NSImage; static func compose(overlay overlayImage: NSImage, settings: CompositionSettings, base: NSImage = standardFolderIcon) -> NSImage?; static func calculateRect(for:in:settings:) -> NSRect }` (calculateRect は変更なし)
- 旧 `compose(folderPath:customImage:settings:)` は削除。

- [ ] **Step 1: テストを更新**

`FolderArtTests/IconComposerTests.swift` の `makeTestImage` と `testComposeReturnsNonNilImage` を次に置き換え、末尾に冪等性テストを足す (geometry テスト 4 本はそのまま):

```swift
    func testComposeReturnsNonNilImage() {
        let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .center, scale: 0.6, opacity: 0.9)
        let result = IconComposer.compose(overlay: overlay, settings: settings)
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, IconComposer.iconSize)
        XCTAssertEqual(TestSupport.pixelSize(of: result!), IconComposer.iconSize)
    }

    func testComposeIsDeterministicAndDoesNotStack() {
        // 標準フォルダアイコンを土台にするので、同じ入力なら何度合成しても同じ結果
        let overlay = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .badge, scale: 0.8, opacity: 1.0, clipToFolderShape: false)
        let a = IconComposer.compose(overlay: overlay, settings: settings)!
        let b = IconComposer.compose(overlay: overlay, settings: settings)!
        XCTAssertEqual(TestSupport.pngData(a), TestSupport.pngData(b))
        XCTAssertTrue(TestSupport.contains(color: .red, in: a))
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/IconComposerTests`)
Expected: ビルドエラー (`compose(overlay:settings:)` が無い)

- [ ] **Step 3: 実装**

`FolderArt/Services/IconComposer.swift` を丸ごと置き換え (calculateRect の本体は現行 132〜186 行と同一):

```swift
import AppKit
import CoreGraphics
import UniformTypeIdentifiers

enum IconComposer {
    static let iconSize = CGSize(width: 512, height: 512)

    /// 合成の土台。加工済みフォルダへの再適用で重ね塗りにならないよう、常に標準アイコンを使う
    static let standardFolderIcon: NSImage = {
        let icon = NSWorkspace.shared.icon(for: .folder)
        icon.size = iconSize
        return icon
    }()

    /// 土台アイコンにオーバーレイ画像 (OverlayRenderer の出力) を合成して返す
    static func compose(
        overlay overlayImage: NSImage,
        settings: CompositionSettings,
        base: NSImage = standardFolderIcon
    ) -> NSImage? {
        let size = iconSize
        let overlayRect = calculateRect(for: overlayImage.size, in: size, settings: settings)

        return BitmapCanvas.draw(size: size) { _ in
            base.draw(in: NSRect(origin: .zero, size: size),
                      from: NSRect(origin: .zero, size: base.size),
                      operation: .sourceOver, fraction: 1)

            if settings.clipToFolderShape {
                if let clipped = makeClipped(overlayImage: overlayImage, overlayRect: overlayRect,
                                             base: base, containerSize: size, opacity: settings.opacity) {
                    clipped.draw(in: NSRect(origin: .zero, size: size))
                }
            } else {
                overlayImage.draw(in: overlayRect,
                                  from: NSRect(origin: .zero, size: overlayImage.size),
                                  operation: .sourceOver, fraction: settings.opacity)
            }
        }
    }

    /// オーバーレイを土台アイコンのアルファ形状で切り抜く (destinationIn)
    private static func makeClipped(
        overlayImage: NSImage, overlayRect: NSRect, base: NSImage,
        containerSize: CGSize, opacity: Double
    ) -> NSImage? {
        BitmapCanvas.draw(size: containerSize) { _ in
            overlayImage.draw(in: overlayRect,
                              from: NSRect(origin: .zero, size: overlayImage.size),
                              operation: .sourceOver, fraction: opacity)
            base.draw(in: NSRect(origin: .zero, size: containerSize),
                      from: NSRect(origin: .zero, size: base.size),
                      operation: .destinationIn, fraction: 1.0)
        }
    }

    /// 配置設定に基づいてオーバーレイの描画 Rect を計算する (現行と同一)
    static func calculateRect(
        for imageSize: CGSize,
        in containerSize: CGSize,
        settings: CompositionSettings
    ) -> NSRect {
        // ここに現行 IconComposer.swift 137〜185 行の本体をそのまま貼る
        let aspectRatio = imageSize.width > 0 ? imageSize.width / imageSize.height : 1.0
        let customWidth: CGFloat
        let customHeight: CGFloat

        switch settings.position {
        case .center:
            if settings.clipToFolderShape {
                let containerAspect = containerSize.width / containerSize.height
                if aspectRatio >= containerAspect {
                    customHeight = containerSize.height
                    customWidth  = customHeight * aspectRatio
                } else {
                    customWidth  = containerSize.width
                    customHeight = customWidth / aspectRatio
                }
            } else {
                let maxDimension = min(containerSize.width, containerSize.height) * settings.scale
                if aspectRatio >= 1 {
                    customWidth  = maxDimension
                    customHeight = maxDimension / aspectRatio
                } else {
                    customHeight = maxDimension
                    customWidth  = maxDimension * aspectRatio
                }
            }
            let x = (containerSize.width  - customWidth)  / 2
            let yBase = (containerSize.height - customHeight) / 2
            let yShift = containerSize.height * settings.verticalOffset
            return NSRect(x: x, y: yBase + yShift, width: customWidth, height: customHeight)

        case .badge:
            let badgeMax = min(containerSize.width, containerSize.height) * settings.scale * 0.45
            if aspectRatio >= 1 {
                customWidth  = badgeMax
                customHeight = badgeMax / aspectRatio
            } else {
                customHeight = badgeMax
                customWidth  = badgeMax * aspectRatio
            }
            let padding: CGFloat = 20
            let x = containerSize.width  - customWidth  - padding
            let yShift = containerSize.height * settings.verticalOffset
            return NSRect(x: x, y: padding + yShift, width: customWidth, height: customHeight)
        }
    }
}
```

`FolderArt/ContentViewModel.swift` 34〜45 行目 (暫定。Task 13 で削除):

```swift
    func updatePreview() {
        guard selectedFolderURL != nil, let image = selectedImage else {
            previewImage = nil
            return
        }
        previewImage = IconComposer.compose(overlay: image, settings: settings)
    }
```

- [ ] **Step 4: テスト**

Run: テスト実行 (全体)
Expected: IconComposerTests 6 PASS。ContentViewModelTests も PASS。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/IconComposer.swift FolderArt/ContentViewModel.swift FolderArtTests/IconComposerTests.swift
git commit -m "refactor: ♻️ IconComposer を標準フォルダアイコン土台のオーバーレイ合成に変更"
```

---

### Task 8: SymbolCatalog と制限記号の fallback リスト

**Files:**
- Create: `FolderArt/Services/SymbolCatalog.swift`
- Create: `FolderArt/Resources/restricted-symbols.txt`
- Test: `FolderArtTests/SymbolCatalogTests.swift`

**Interfaces:**
- Produces:
  - `struct SymbolCatalog { let names: [String]; func search(_ query: String, limit: Int = 240) -> [String]; static func load(bundle: Bundle = .main) -> SymbolCatalog; static func restrictedNames(bundle: Bundle) -> Set<String>; static let coreGlyphsResources: URL }`
  - `SymbolCatalog.popularNames: [String]` (検索語が空のときに先頭に出す 40 個)

- [ ] **Step 1: fallback リストを生成**

```bash
mkdir -p FolderArt/Resources
plutil -convert json -o - /System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources/symbol_restrictions.strings \
  | python3 -c 'import json,sys; print("\n".join(sorted(json.load(sys.stdin))))' \
  > FolderArt/Resources/restricted-symbols.txt
wc -l FolderArt/Resources/restricted-symbols.txt   # 525 前後
```

`project.yml` の `targets.FolderArt.sources` は `path: FolderArt` なので、`.txt` は XcodeGen が自動でリソースとして扱う。`xcodegen generate` 後に `FolderArt.xcodeproj` の Copy Bundle Resources に入っていることを Step 4 で確認する。

- [ ] **Step 2: テストを書く**

`FolderArtTests/SymbolCatalogTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class SymbolCatalogTests: XCTestCase {

    func testRestrictedSymbolsAreExcluded() {
        let catalog = SymbolCatalog.load(bundle: Bundle(for: SymbolCatalogTests.self))
        let restricted = SymbolCatalog.restrictedNames(bundle: Bundle(for: SymbolCatalogTests.self))
        XCTAssertGreaterThan(restricted.count, 400)
        XCTAssertTrue(restricted.contains("airplay.audio"))   // symbol_restrictions.strings に必ずある
        XCTAssertTrue(Set(catalog.names).isDisjoint(with: restricted))
        XCTAssertGreaterThan(catalog.names.count, 3000)
    }

    func testEveryCatalogNameIsRenderable() {
        // 抜き取りで 200 個: NSImage(systemSymbolName:) が nil を返さない
        let catalog = SymbolCatalog.load()
        for name in catalog.names.prefix(200) {
            XCTAssertNotNil(NSImage(systemSymbolName: name, accessibilityDescription: nil), name)
        }
    }

    func testSearchMatchesNameAndTerms() {
        let catalog = SymbolCatalog.load()
        let byName = catalog.search("folder")
        XCTAssertTrue(byName.contains("folder"))
        XCTAssertTrue(byName.contains("folder.fill"))
        XCTAssertTrue(byName.allSatisfy { !$0.isEmpty })

        let byTerm = catalog.search("sports")      // symbol_search.plist の検索語
        XCTAssertFalse(byTerm.isEmpty)

        XCTAssertEqual(catalog.search("").prefix(5).map { $0 }, Array(SymbolCatalog.popularNames.prefix(5)))
    }

    func testFallbackListIsBundled() {
        let url = Bundle(for: SymbolCatalogTests.self).url(forResource: "restricted-symbols", withExtension: "txt")
            ?? Bundle.main.url(forResource: "restricted-symbols", withExtension: "txt")
        XCTAssertNotNil(url)
    }
}
```

テストバンドルは `@testable import FolderArt` 経由でアプリの `Bundle.main` を持つので、`restrictedNames(bundle:)` はまず渡されたバンドル、次に `Bundle.main` の順で探す実装にする。

- [ ] **Step 3: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/SymbolCatalogTests`)
Expected: ビルドエラー (`SymbolCatalog` 未定義)

- [ ] **Step 4: 実装**

`FolderArt/Services/SymbolCatalog.swift`:

```swift
import Foundation

/// 実行中の macOS が持つ SF Symbols のカタログ。制限付き記号 (Apple 製品・機能を表すもの) は除外する。
struct SymbolCatalog {
    let names: [String]
    private let searchTerms: [String: [String]]

    static let coreGlyphsResources = URL(fileURLWithPath:
        "/System/Library/CoreServices/CoreGlyphs.bundle/Contents/Resources")

    /// 検索語が空のときに先頭に出す定番
    static let popularNames: [String] = [
        "star.fill", "heart.fill", "folder.fill", "doc.fill", "photo.fill", "camera.fill",
        "music.note", "film.fill", "book.fill", "pencil", "paintbrush.fill", "hammer.fill",
        "wrench.fill", "gearshape.fill", "briefcase.fill", "cart.fill", "creditcard.fill",
        "house.fill", "building.2.fill", "car.fill", "airplane", "globe", "map.fill",
        "calendar", "clock.fill", "bell.fill", "flag.fill", "tag.fill", "bookmark.fill",
        "lock.fill", "key.fill", "trash.fill", "archivebox.fill", "tray.full.fill",
        "person.fill", "person.2.fill", "gamecontroller.fill", "graduationcap.fill",
        "leaf.fill", "flame.fill"
    ]

    static func load(bundle: Bundle = .main) -> SymbolCatalog {
        let restricted = restrictedNames(bundle: bundle)
        let available = availableNames()
        let names = available.subtracting(restricted).sorted()
        let terms = (try? loadStringArrayDict(coreGlyphsResources.appendingPathComponent("symbol_search.plist"))) ?? [:]
        return SymbolCatalog(names: names, searchTerms: terms)
    }

    /// 名前の部分一致、または検索語の前方一致。空なら popularNames を先頭に全件。
    func search(_ query: String, limit: Int = 240) -> [String] {
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        if q.isEmpty {
            let set = Set(names)
            let popular = Self.popularNames.filter { set.contains($0) }
            return Array((popular + names.filter { !popular.contains($0) }).prefix(limit))
        }
        var result: [String] = []
        for name in names {
            if name.contains(q) || (searchTerms[name]?.contains { $0.lowercased().hasPrefix(q) } ?? false) {
                result.append(name)
                if result.count >= limit { break }
            }
        }
        return result
    }

    // MARK: - Loading

    /// CoreGlyphs の symbol_restrictions.strings。読めなければ同梱 restricted-symbols.txt。
    static func restrictedNames(bundle: Bundle) -> Set<String> {
        let live = coreGlyphsResources.appendingPathComponent("symbol_restrictions.strings")
        if let data = try? Data(contentsOf: live),
           let dict = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
           !dict.isEmpty {
            return Set(dict.keys)
        }
        for b in [bundle, Bundle.main] {
            if let url = b.url(forResource: "restricted-symbols", withExtension: "txt"),
               let text = try? String(contentsOf: url) {
                return Set(text.split(separator: "\n").map(String.init).filter { !$0.isEmpty })
            }
        }
        return []
    }

    /// name_availability.plist の symbols キー。読めなければ popularNames。
    private static func availableNames() -> Set<String> {
        let url = coreGlyphsResources.appendingPathComponent("name_availability.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let symbols = root["symbols"] as? [String: String] else {
            return Set(popularNames)
        }
        return Set(symbols.keys)
    }

    private static func loadStringArrayDict(_ url: URL) throws -> [String: [String]] {
        let data = try Data(contentsOf: url)
        return try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: [String]] ?? [:]
    }
}
```

- [ ] **Step 5: テスト**

Run: `xcodegen generate` → `grep -c "restricted-symbols.txt" FolderArt.xcodeproj/project.pbxproj` が 1 以上 → テスト実行 (`-only-testing:FolderArtTests/SymbolCatalogTests`)
Expected: 4 tests PASS

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Services/SymbolCatalog.swift FolderArt/Resources/restricted-symbols.txt FolderArtTests/SymbolCatalogTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ SymbolCatalog を追加 (制限付き SF Symbols を除外して検索)"
```

---

### Task 9: FolderIconManager の整理 (setfile 削除、throws 化、テスト修正)

**Files:**
- Modify: `FolderArt/Services/FolderIconManager.swift`
- Modify: `FolderArt/ContentViewModel.swift:65-69` (暫定: 呼び出し側)
- Test: `FolderArtTests/FolderIconManagerTests.swift`

現状の確認 (2026-09-02 のベースライン): 19 tests 中 `testBackupReturnsPath` が 1 件失敗。テスト実行ログに `xcrun: error: cannot be used within an App Sandbox.` が出るのは `/usr/bin/setfile` (xcrun のシムをサンドボックス内から起動している) が原因で、このタスクで消える。

**Interfaces:**
- Produces:
  - `enum FolderIconError: LocalizedError { case applyFailed(URL); case folderNotFound(URL) }`
  - `FolderIconManager.applyIcon(_ icon: NSImage, to folderURL: URL) throws` (Bool 返却をやめる)
  - `backupCurrentIcon(for:) throws -> URL?`, `resetIcon(for:backupURL:)` は変更なし

- [ ] **Step 1: テストを更新**

`FolderArtTests/FolderIconManagerTests.swift` の `testBackupReturnsPath` と `testApplyAndResetIcon` を置き換え:

```swift
    func testBackupReturnsNilWhenFolderHasNoCustomIcon() throws {
        let manager = FolderIconManager()
        XCTAssertNil(try manager.backupCurrentIcon(for: testFolderURL))
    }

    func testBackupReturnsPathWhenCustomIconExists() throws {
        let manager = FolderIconManager()
        let icon = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
        try manager.applyIcon(icon, to: testFolderURL)          // Icon\r ができる
        let backupURL = try XCTUnwrap(try manager.backupCurrentIcon(for: testFolderURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        manager.resetIcon(for: testFolderURL, backupURL: nil)
        try? FileManager.default.removeItem(at: backupURL.deletingLastPathComponent())
    }

    func testApplyAndResetIcon() throws {
        let manager = FolderIconManager()
        let icon = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
        try manager.applyIcon(icon, to: testFolderURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFolderURL.appendingPathComponent("Icon\r").path))
        manager.resetIcon(for: testFolderURL, backupURL: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFolderURL.appendingPathComponent("Icon\r").path))
    }

    func testApplyToMissingFolderThrows() {
        let manager = FolderIconManager()
        let missing = testFolderURL.appendingPathComponent("does-not-exist")
        let icon = TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)
        XCTAssertThrowsError(try manager.applyIcon(icon, to: missing))
    }
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/FolderIconManagerTests`)
Expected: ビルドエラー (`applyIcon` が throws でない)

- [ ] **Step 3: 実装**

`FolderArt/Services/FolderIconManager.swift` の 47〜60 行目を置き換え、先頭にエラー型を足す:

```swift
enum FolderIconError: LocalizedError {
    case folderNotFound(URL)
    case applyFailed(URL)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let url):
            return String(localized: "フォルダーが見つかりません: \(url.lastPathComponent)")
        case .applyFailed(let url):
            return String(localized: "アイコンを適用できません: \(url.lastPathComponent)。書き込み権限を確認してください。")
        }
    }
}
```

```swift
    /// 合成済みアイコンをフォルダーに適用する。失敗は throw。
    func applyIcon(_ icon: NSImage, to folderURL: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderIconError.folderNotFound(folderURL)
        }
        // NSWorkspace.setIcon が custom icon bit を立てる。setfile は Xcode 付属で多くの Mac に無いため使わない。
        guard NSWorkspace.shared.setIcon(icon, forFile: folderURL.path, options: []) else {
            throw FolderIconError.applyFailed(folderURL)
        }
    }
```

`FolderArt/ContentViewModel.swift` 64〜69 行目 (暫定):

```swift
            try iconManager.applyIcon(composedImage, to: folderURL)
```

- [ ] **Step 4: テスト**

Run: テスト実行 (全体)
Expected: FolderIconManagerTests 5 PASS。全体 PASS (これで既知の失敗が消える)。

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/FolderIconManager.swift FolderArt/ContentViewModel.swift FolderArtTests/FolderIconManagerTests.swift
git commit -m "fix: 🐛 setfile 依存を削除し applyIcon を throws 化、バックアップのテストを実装に合わせる"
```

---

### Task 10: FolderSelection (複数フォルダと行選択)

**Files:**
- Create: `FolderArt/State/FolderSelection.swift`
- Test: `FolderArtTests/FolderSelectionTests.swift`

**Interfaces:**
- Produces: `@MainActor final class FolderSelection: ObservableObject { @Published private(set) var folders: [URL]; @Published var selectedIDs: Set<URL>; var targets: [URL]; var isEmpty: Bool; func add(_ urls: [URL]); func remove(_ url: URL); func removeAll(); func clearSelection() }`
- `add` はディレクトリだけを受け付け、`standardizedFileURL` で重複を除く。

- [ ] **Step 1: テストを書く**

`FolderArtTests/FolderSelectionTests.swift`:

```swift
import XCTest
@testable import FolderArt

@MainActor
final class FolderSelectionTests: XCTestCase {
    private var root: URL!
    private var a: URL!, b: URL!, c: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSelectionTests_\(UUID().uuidString)")
        a = root.appendingPathComponent("A"); b = root.appendingPathComponent("B"); c = root.appendingPathComponent("C")
        for d in [a, b, c] { try FileManager.default.createDirectory(at: d!, withIntermediateDirectories: true) }
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddDedupesAndIgnoresFiles() throws {
        let file = root.appendingPathComponent("file.txt")
        try "x".data(using: .utf8)!.write(to: file)
        let sel = FolderSelection()
        sel.add([a, b, a, file, URL(fileURLWithPath: a.path + "/")])
        XCTAssertEqual(sel.folders.map(\.lastPathComponent), ["A", "B"])
    }

    func testTargetsAreAllWhenNothingSelected() {
        let sel = FolderSelection()
        sel.add([a, b, c])
        XCTAssertEqual(sel.targets.count, 3)
        sel.selectedIDs = [b.standardizedFileURL]
        XCTAssertEqual(sel.targets.map(\.lastPathComponent), ["B"])
        sel.clearSelection()
        XCTAssertEqual(sel.targets.count, 3)
    }

    func testRemoveAlsoClearsSelectionOfThatFolder() {
        let sel = FolderSelection()
        sel.add([a, b])
        sel.selectedIDs = [a.standardizedFileURL, b.standardizedFileURL]
        sel.remove(a)
        XCTAssertEqual(sel.folders.map(\.lastPathComponent), ["B"])
        XCTAssertEqual(sel.selectedIDs, [b.standardizedFileURL])
        sel.removeAll()
        XCTAssertTrue(sel.isEmpty)
        XCTAssertTrue(sel.selectedIDs.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/FolderSelectionTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/State/FolderSelection.swift`:

```swift
import Foundation
import Combine

/// 適用先フォルダのリストと、その中の選択。
@MainActor
final class FolderSelection: ObservableObject {
    @Published private(set) var folders: [URL] = []
    /// List の selection。要素は folders と同じ standardizedFileURL
    @Published var selectedIDs: Set<URL> = []

    var isEmpty: Bool { folders.isEmpty }

    /// 適用対象: 選択があれば選択分、無ければ全件
    var targets: [URL] {
        if selectedIDs.isEmpty { return folders }
        return folders.filter { selectedIDs.contains($0) }
    }

    func add(_ urls: [URL]) {
        var existing = Set(folders)
        for raw in urls {
            let url = raw.standardizedFileURL
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue,
                  !existing.contains(url) else { continue }
            folders.append(url)
            existing.insert(url)
        }
    }

    func remove(_ url: URL) {
        let target = url.standardizedFileURL
        folders.removeAll { $0 == target }
        selectedIDs.remove(target)
    }

    func removeAll() {
        folders = []
        selectedIDs = []
    }

    func clearSelection() {
        selectedIDs = []
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/FolderSelectionTests`)
Expected: 3 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/State/FolderSelection.swift FolderArtTests/FolderSelectionTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ FolderSelection を追加 (複数フォルダと行選択)"
```

---

### Task 11: OverlayState (タブごとの入力とプレビュー)

**Files:**
- Create: `FolderArt/State/OverlayState.swift`
- Test: `FolderArtTests/OverlayStateTests.swift`

**Interfaces:**
- Consumes: `OverlayRenderer.render`, `IconComposer.compose`, `AssetStore`
- Produces:
  ```swift
  @MainActor final class OverlayState: ObservableObject {
      enum Tab: String, CaseIterable, Identifiable { case image, symbol, emoji, text }
      @Published var activeTab: Tab
      @Published var imageAssetID: UUID?
      @Published var symbolName: String?
      @Published var emoji: String
      @Published var text: String
      @Published var settings: CompositionSettings
      @Published private(set) var overlayImage: NSImage?   // レンダラー出力 (512px)
      @Published private(set) var previewImage: NSImage?   // 合成結果 (512px)
      let assets: AssetStore
      var overlay: Overlay?          // activeTab から導出。空なら nil
      var canApply: Bool             // previewImage != nil
      init(assets: AssetStore, debounce: TimeInterval = 0.1)
      func selectImage(url: URL) throws   // AssetStore に複製し image タブへ
      func restore(overlay: Overlay, settings: CompositionSettings)  // お気に入りから復元
      func updatePreviewNow()
  }
  ```
- `Tab.title: LocalizedStringKey` は View 側 (Task 14) で定義する。

- [ ] **Step 1: テストを書く**

`FolderArtTests/OverlayStateTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class OverlayStateTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("OverlayStateTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    func testOverlayFollowsActiveTab() {
        let state = OverlayState(assets: assets)
        XCTAssertNil(state.overlay)
        state.activeTab = .text; state.text = "26"
        XCTAssertEqual(state.overlay, .text("26"))
        state.activeTab = .emoji
        XCTAssertNil(state.overlay)               // 絵文字は未入力
        state.emoji = "🎵"
        XCTAssertEqual(state.overlay, .emoji("🎵"))
        state.activeTab = .symbol; state.symbolName = "star.fill"
        XCTAssertEqual(state.overlay, .symbol(name: "star.fill"))
        state.activeTab = .text                   // 入力はタブごとに保持される
        XCTAssertEqual(state.overlay, .text("26"))
    }

    func testPreviewIsNilWithoutInputAndGeneratedWithInput() {
        let state = OverlayState(assets: assets)
        state.updatePreviewNow()
        XCTAssertNil(state.previewImage)
        XCTAssertFalse(state.canApply)

        state.activeTab = .symbol; state.symbolName = "star.fill"
        state.updatePreviewNow()
        XCTAssertNotNil(state.overlayImage)
        XCTAssertNotNil(state.previewImage)
        XCTAssertEqual(state.previewImage?.size, IconComposer.iconSize)
        XCTAssertTrue(state.canApply)
    }

    func testDebouncedPreviewUpdatesAfterChange() async {
        let state = OverlayState(assets: assets, debounce: 0.05)
        state.activeTab = .text
        state.text = "A"
        try? await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertNotNil(state.previewImage)
    }

    func testSelectImageCopiesIntoAssetStoreAndSwitchesTab() throws {
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let src = dir.appendingPathComponent("src.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 20, height: 20), color: .green)).write(to: src)

        let state = OverlayState(assets: assets)
        state.activeTab = .text
        try state.selectImage(url: src)
        XCTAssertEqual(state.activeTab, .image)
        let id = try XCTUnwrap(state.imageAssetID)
        XCTAssertNotNil(assets.image(for: id))
        XCTAssertEqual(state.overlay, .image(assetID: id))
    }

    func testRestoreFromPresetSetsTabInputAndSettings() {
        let state = OverlayState(assets: assets)
        var settings = CompositionSettings()
        settings.position = .badge
        settings.tintColor = .black
        state.restore(overlay: .emoji("📷"), settings: settings)
        XCTAssertEqual(state.activeTab, .emoji)
        XCTAssertEqual(state.emoji, "📷")
        XCTAssertEqual(state.settings, settings)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/OverlayStateTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/State/OverlayState.swift`:

```swift
import AppKit
import Combine

/// 4 タブの入力と、そこから作るプレビュー。
@MainActor
final class OverlayState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case image, symbol, emoji, text
        var id: String { rawValue }
    }

    @Published var activeTab: Tab = .image
    @Published var imageAssetID: UUID?
    @Published var symbolName: String?
    @Published var emoji: String = ""
    @Published var text: String = ""
    @Published var settings = CompositionSettings()

    @Published private(set) var overlayImage: NSImage?
    @Published private(set) var previewImage: NSImage?

    let assets: AssetStore
    private var cancellable: AnyCancellable?

    init(assets: AssetStore, debounce: TimeInterval = 0.1) {
        self.assets = assets
        // objectWillChange は変更前に飛ぶが、debounce 後には値が反映されている
        cancellable = objectWillChange
            .debounce(for: .seconds(debounce), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePreviewNow() }
    }

    /// 現在のタブの入力から Overlay を作る。未入力なら nil。
    var overlay: Overlay? {
        switch activeTab {
        case .image:
            return imageAssetID.map { .image(assetID: $0) }
        case .symbol:
            return symbolName.map { .symbol(name: $0) }
        case .emoji:
            let s = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : .emoji(s)
        case .text:
            let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : .text(s)
        }
    }

    var canApply: Bool { previewImage != nil }

    /// 画像ファイルを AssetStore に複製して画像タブに切り替える
    func selectImage(url: URL) throws {
        let id = try assets.store(contentsOf: url)
        imageAssetID = id
        activeTab = .image
    }

    /// お気に入りからの復元
    func restore(overlay: Overlay, settings: CompositionSettings) {
        switch overlay {
        case .image(let id):      imageAssetID = id;  activeTab = .image
        case .symbol(let name):   symbolName = name;  activeTab = .symbol
        case .emoji(let s):       emoji = s;          activeTab = .emoji
        case .text(let s):        text = s;           activeTab = .text
        case .legacyImage:        return
        }
        self.settings = settings
        updatePreviewNow()
    }

    func updatePreviewNow() {
        guard let overlay,
              let rendered = OverlayRenderer.render(overlay, settings: settings,
                                                    side: IconComposer.iconSize.width, assets: assets) else {
            overlayImage = nil
            previewImage = nil
            return
        }
        overlayImage = rendered
        previewImage = IconComposer.compose(overlay: rendered, settings: settings)
    }
}
```

注意: `updatePreviewNow()` 内で `overlayImage` / `previewImage` に代入すると `objectWillChange` が再び飛び、debounce 後にもう一度 `updatePreviewNow()` が走る。結果は同じで冪等だが、無駄な再描画を避けるため、代入前に「変わらないなら代入しない」ガードを入れる:

```swift
        // updatePreviewNow の先頭で
        let newOverlay = overlay
        if newOverlay == lastRenderedOverlay && settings == lastRenderedSettings { return }
        lastRenderedOverlay = newOverlay
        lastRenderedSettings = settings
```

`private var lastRenderedOverlay: Overlay?` と `private var lastRenderedSettings: CompositionSettings?` をプロパティに足す。`restore` で `updatePreviewNow()` を呼ぶ前にこの2つを nil に戻す必要はない (値が変わるので通る)。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/OverlayStateTests`)
Expected: 5 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/State/OverlayState.swift FolderArtTests/OverlayStateTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ OverlayState を追加 (4 タブの入力とデバウンス付きプレビュー)"
```

---

### Task 12: ApplyCoordinator (一括適用)

**Files:**
- Create: `FolderArt/Services/ApplyCoordinator.swift`
- Test: `FolderArtTests/ApplyCoordinatorTests.swift`

**Interfaces:**
- Consumes: `FolderIconManager.backupCurrentIcon/applyIcon`, `BookmarkManager.createBookmark`, `HistoryStore.upsert`, `IconComposer.compose`
- Produces:
  ```swift
  struct ApplyFailure: Identifiable { let id = UUID(); let folder: URL; let reason: String }
  struct ApplyOutcome { let succeeded: [URL]; let failed: [ApplyFailure]; var summary: String? }  // 全成功なら nil
  @MainActor final class ApplyCoordinator {
      init(history: HistoryStore, iconManager: FolderIconManager = FolderIconManager())
      func apply(overlayImage: NSImage, overlay: Overlay, settings: CompositionSettings,
                 to folders: [URL], progress: @escaping (Int, Int) -> Void = { _, _ in }) async -> ApplyOutcome
      func reset(_ task: IconTask) throws        // 履歴の 1 行をリセット (ブックマーク経由)
      func reset(folder: URL) throws             // 同一セッション用 (URL 直接)
  }
  ```
- `overlayImage` は `OverlayState.overlayImage` (レンダラー出力) を渡す。合成は 1 回。

- [ ] **Step 1: テストを書く**

`FolderArtTests/ApplyCoordinatorTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class ApplyCoordinatorTests: XCTestCase {
    private var root: URL!
    private var historyURL: URL!
    private var history: HistoryStore!
    private var coordinator: ApplyCoordinator!
    private var overlayImage: NSImage!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ApplyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        historyURL = root.appendingPathComponent("history.json")
        history = HistoryStore(storageURL: historyURL)
        coordinator = ApplyCoordinator(history: history)
        overlayImage = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
    }
    override func tearDown() async throws {
        for url in history.tasks.map({ URL(fileURLWithPath: $0.folderPath) }) {
            NSWorkspace.shared.setIcon(nil, forFile: url.path, options: [])
        }
        try? FileManager.default.removeItem(at: root)
    }

    private func folder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    func testPartialFailureKeepsSuccesses() async throws {
        let a = try folder("A"), b = try folder("B")
        let missing = root.appendingPathComponent("missing")
        var progress: [(Int, Int)] = []

        let outcome = await coordinator.apply(
            overlayImage: overlayImage, overlay: .text("x"), settings: CompositionSettings(),
            to: [a, missing, b], progress: { progress.append(($0, $1)) })

        XCTAssertEqual(outcome.succeeded.map(\.lastPathComponent), ["A", "B"])
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertEqual(outcome.failed.first?.folder.lastPathComponent, "missing")
        XCTAssertNotNil(outcome.summary)
        XCTAssertEqual(history.tasks.count, 2)
        XCTAssertEqual(progress.last?.0, 3)
        XCTAssertEqual(progress.last?.1, 3)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))
    }

    func testReapplyReplacesHistoryRow() async throws {
        let a = try folder("A")
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("2"),
                                    settings: CompositionSettings(), to: [a])
        XCTAssertEqual(history.tasks.count, 1)
        XCTAssertEqual(history.tasks.first?.overlay, .text("2"))
    }

    func testAllSuccessHasNoSummary() async throws {
        let a = try folder("A")
        let outcome = await coordinator.apply(overlayImage: overlayImage, overlay: .emoji("🎵"),
                                              settings: CompositionSettings(), to: [a])
        XCTAssertNil(outcome.summary)
        XCTAssertTrue(outcome.failed.isEmpty)
    }

    func testResetRemovesIconAndHistory() async throws {
        let a = try folder("A")
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        let task = try XCTUnwrap(history.task(forFolderPath: a.standardizedFileURL.path))
        try coordinator.reset(task)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))
        XCTAssertTrue(history.tasks.isEmpty)
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/ApplyCoordinatorTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/Services/ApplyCoordinator.swift`:

```swift
import AppKit

struct ApplyFailure: Identifiable {
    let id = UUID()
    let folder: URL
    let reason: String
}

struct ApplyOutcome {
    let succeeded: [URL]
    let failed: [ApplyFailure]

    /// 一部失敗のときだけ文言を返す。全成功なら nil。
    var summary: String? {
        guard !failed.isEmpty else { return nil }
        let lines = failed.map { "・\($0.folder.lastPathComponent): \($0.reason)" }.joined(separator: "\n")
        return String(localized: "\(succeeded.count) 件成功、\(failed.count) 件失敗") + "\n\n" + lines
    }
}

enum ApplyError: LocalizedError {
    case composeFailed
    case bookmarkUnavailable

    var errorDescription: String? {
        switch self {
        case .composeFailed:       return String(localized: "アイコンの合成に失敗しました")
        case .bookmarkUnavailable: return String(localized: "フォルダーへのアクセスが無効になっています。")
        }
    }
}

/// 1 つのオーバーレイを複数フォルダに適用する。1 件の失敗で止めず、結果を集めて返す。
@MainActor
final class ApplyCoordinator {
    private let history: HistoryStore
    private let iconManager: FolderIconManager

    init(history: HistoryStore, iconManager: FolderIconManager = FolderIconManager()) {
        self.history = history
        self.iconManager = iconManager
    }

    func apply(
        overlayImage: NSImage,
        overlay: Overlay,
        settings: CompositionSettings,
        to folders: [URL],
        progress: @escaping (Int, Int) -> Void = { _, _ in }
    ) async -> ApplyOutcome {
        // 合成は 1 回だけ。メインスレッドを塞がないよう別タスクで描く。
        let composed: NSImage? = await Task.detached(priority: .userInitiated) {
            IconComposer.compose(overlay: overlayImage, settings: settings)
        }.value

        guard let icon = composed else {
            let failures = folders.map { ApplyFailure(folder: $0, reason: ApplyError.composeFailed.localizedDescription) }
            return ApplyOutcome(succeeded: [], failed: failures)
        }

        var succeeded: [URL] = []
        var failed: [ApplyFailure] = []
        let total = folders.count

        for (index, folder) in folders.enumerated() {
            do {
                let backupURL = try iconManager.backupCurrentIcon(for: folder)
                let bookmark = try BookmarkManager.createBookmark(for: folder)
                try iconManager.applyIcon(icon, to: folder)
                let task = IconTask(
                    folderPath: folder.standardizedFileURL.path,
                    bookmarkData: bookmark,
                    backupPath: backupURL?.path,
                    overlay: overlay,
                    settings: settings
                )
                try history.upsert(task)
                succeeded.append(folder)
            } catch {
                failed.append(ApplyFailure(folder: folder, reason: error.localizedDescription))
            }
            progress(index + 1, total)
            await Task.yield()   // 進捗表示を描画させる
        }
        return ApplyOutcome(succeeded: succeeded, failed: failed)
    }

    /// 履歴の 1 行をリセット (別セッション再開用: ブックマーク経由)
    func reset(_ task: IconTask) throws {
        guard let url = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            throw ApplyError.bookmarkUnavailable
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        iconManager.resetIcon(for: url, backupURL: task.backupPath.map { URL(fileURLWithPath: $0) })
        try history.remove(task)
    }

    /// 同一セッション用: URL を直接使ってリセット
    func reset(folder: URL) throws {
        let path = folder.standardizedFileURL.path
        let task = history.task(forFolderPath: path)
        iconManager.resetIcon(for: folder, backupURL: task?.backupPath.map { URL(fileURLWithPath: $0) })
        if let task { try history.remove(task) }
    }
}
```

`NSImage` は `Sendable` ではないため、`Task.detached` に渡す箇所で Swift 5.9 の strict concurrency 警告が出る場合は `nonisolated(unsafe)` ではなく、クロージャ内で `overlayImage` をキャプチャする現在の形のまま警告を許容する (エラーにはならない)。

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (`-only-testing:FolderArtTests/ApplyCoordinatorTests`)
Expected: 4 tests PASS

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/ApplyCoordinator.swift FolderArtTests/ApplyCoordinatorTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ ApplyCoordinator を追加 (複数フォルダへの一括適用と部分失敗の集計)"
```

---

### Task 13: AppModel (glue) と ContentViewModel の削除

**Files:**
- Create: `FolderArt/AppModel.swift`
- Delete: `FolderArt/ContentViewModel.swift`, `FolderArtTests/ContentViewModelTests.swift`
- Modify: `FolderArt/ContentView.swift` (AppModel に差し替えて **ビルドを通すだけ** の最小変更。UI の作り直しは Task 14〜19)
- Test: `FolderArtTests/AppModelTests.swift`

**Interfaces:**
- Produces:
  ```swift
  @MainActor final class AppModel: ObservableObject {
      let folders: FolderSelection
      let overlay: OverlayState
      let history: HistoryStore
      let presets: PresetStore
      let assets: AssetStore
      @Published var errorMessage: String?
      @Published var isApplying: Bool
      @Published var progress: (done: Int, total: Int)?
      init(history: HistoryStore = HistoryStore(), presets: PresetStore = PresetStore(), assets: AssetStore = AssetStore())
      var canApply: Bool
      var applyButtonTitle: String
      func apply() async
      func resetTargets()
      func reset(task: IconTask)
      func addFolders(_ urls: [URL]); func selectFoldersWithPanel(); func selectImageWithPanel()
      func handleDroppedURLs(_ urls: [URL])      // フォルダ/画像を振り分け
      func saveCurrentAsPreset(); func applyPreset(_ p: Preset); func removePreset(_ p: Preset); func renamePreset(_ p: Preset, to: String)
      func reapAssets()
  }
  ```

- [ ] **Step 1: テストを書く**

`FolderArtTests/AppModelTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class AppModelTests: XCTestCase {
    private var root: URL!
    private var model: AppModel!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("AppModelTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        model = AppModel(
            history: HistoryStore(storageURL: root.appendingPathComponent("history.json")),
            presets: PresetStore(storageURL: root.appendingPathComponent("presets.json")),
            assets: AssetStore(directory: root.appendingPathComponent("assets")))
    }
    override func tearDown() async throws {
        for t in model.history.tasks { NSWorkspace.shared.setIcon(nil, forFile: t.folderPath, options: []) }
        try? FileManager.default.removeItem(at: root)
    }

    func testCanApplyNeedsFoldersAndOverlay() throws {
        XCTAssertFalse(model.canApply)
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        model.addFolders([a])
        XCTAssertFalse(model.canApply)
        model.overlay.activeTab = .text
        model.overlay.text = "x"
        model.overlay.updatePreviewNow()
        XCTAssertTrue(model.canApply)
        XCTAssertEqual(model.applyButtonTitle, String(localized: "1 フォルダに適用"))
        model.folders.selectedIDs = [a.standardizedFileURL]
        XCTAssertEqual(model.applyButtonTitle, String(localized: "選択した 1 フォルダに適用"))
    }

    func testDroppedURLsAreRouted() throws {
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        let png = root.appendingPathComponent("pic.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)).write(to: png)
        model.overlay.activeTab = .text
        model.handleDroppedURLs([a, png])
        XCTAssertEqual(model.folders.folders.count, 1)
        XCTAssertEqual(model.overlay.activeTab, .image)
        XCTAssertNotNil(model.overlay.imageAssetID)
    }

    func testSavePresetAndReapKeepsReferencedAssets() throws {
        let png = root.appendingPathComponent("pic.png")
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red)).write(to: png)
        try model.overlay.selectImage(url: png)
        let used = model.overlay.imageAssetID!
        let orphan = try model.assets.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .blue))
        model.saveCurrentAsPreset()
        XCTAssertEqual(model.presets.presets.count, 1)
        model.reapAssets()
        XCTAssertEqual(model.assets.allIDs(), [used])
        XCTAssertFalse(model.assets.allIDs().contains(orphan))
    }
}
```

- [ ] **Step 2: テストが失敗することを確認**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: ビルドエラー

- [ ] **Step 3: 実装**

`FolderArt/AppModel.swift`:

```swift
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// 画面全体の状態を束ねる。個別の責務は FolderSelection / OverlayState / ApplyCoordinator が持つ。
@MainActor
final class AppModel: ObservableObject {
    let folders: FolderSelection
    let overlay: OverlayState
    let history: HistoryStore
    let presets: PresetStore
    let assets: AssetStore
    private let coordinator: ApplyCoordinator

    @Published var errorMessage: String?
    @Published var isApplying = false
    @Published var progress: (done: Int, total: Int)?

    init(history: HistoryStore = HistoryStore(),
         presets: PresetStore = PresetStore(),
         assets: AssetStore = AssetStore()) {
        self.history = history
        self.presets = presets
        self.assets = assets
        self.folders = FolderSelection()
        self.overlay = OverlayState(assets: assets)
        self.coordinator = ApplyCoordinator(history: history)

        if let e = history.loadError ?? presets.loadError {
            errorMessage = String(localized: "保存データの読み込みに失敗しました: \(e.localizedDescription)")
        }
        reapAssets()
    }

    // MARK: - 適用

    var canApply: Bool { !folders.isEmpty && overlay.canApply && !isApplying }

    var applyButtonTitle: String {
        let n = folders.targets.count
        if isApplying { return String(localized: "適用中…") }
        return folders.selectedIDs.isEmpty
            ? String(localized: "\(n) フォルダに適用")
            : String(localized: "選択した \(n) フォルダに適用")
    }

    func apply() async {
        guard let overlayValue = overlay.overlay, let image = overlay.overlayImage else { return }
        let targets = folders.targets
        guard !targets.isEmpty else { return }
        isApplying = true
        progress = (0, targets.count)
        defer { isApplying = false; progress = nil }

        let outcome = await coordinator.apply(
            overlayImage: image, overlay: overlayValue, settings: overlay.settings,
            to: targets, progress: { [weak self] done, total in self?.progress = (done, total) })
        errorMessage = outcome.summary
        reapAssets()
    }

    // MARK: - リセット

    /// 適用先 (選択 or 全部) のアイコンを戻す
    func resetTargets() {
        for url in folders.targets {
            do { try coordinator.reset(folder: url) }
            catch { errorMessage = error.localizedDescription }
        }
        reapAssets()
    }

    func reset(task: IconTask) {
        do { try coordinator.reset(task) }
        catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    // MARK: - フォルダと画像の入力

    func addFolders(_ urls: [URL]) { folders.add(urls) }

    func selectFoldersWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "追加")
        if panel.runModal() == .OK { folders.add(panel.urls) }
    }

    func selectImageWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP, .tiff]
        panel.prompt = String(localized: "画像を選択")
        if panel.runModal() == .OK, let url = panel.url { selectImage(url) }
    }

    func selectImage(_ url: URL) {
        do { try overlay.selectImage(url: url) }
        catch { errorMessage = error.localizedDescription }
    }

    /// ドロップされた URL をフォルダと画像に振り分ける。画像は最初の 1 枚だけ使う。
    func handleDroppedURLs(_ urls: [URL]) {
        var dirs: [URL] = []
        var firstImage: URL?
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                dirs.append(url)
            } else if firstImage == nil, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                firstImage = url
            }
        }
        if !dirs.isEmpty { folders.add(dirs) }
        if let image = firstImage { selectImage(image) }
    }

    // MARK: - お気に入り

    func saveCurrentAsPreset() {
        guard let o = overlay.overlay else { return }
        do { try presets.add(name: nil, overlay: o, settings: overlay.settings) }
        catch { errorMessage = error.localizedDescription }
    }

    func applyPreset(_ preset: Preset) {
        overlay.restore(overlay: preset.overlay, settings: preset.settings)
    }

    func removePreset(_ preset: Preset) {
        do { try presets.remove(preset) } catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    func renamePreset(_ preset: Preset, to name: String) {
        do { try presets.rename(preset, to: name) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - 画像の回収

    /// 履歴・お気に入り・現在の選択のどれからも参照されない PNG を消す
    func reapAssets() {
        var keep = history.referencedAssetIDs.union(presets.referencedAssetIDs)
        if let id = overlay.imageAssetID { keep.insert(id) }
        try? assets.reap(keeping: keep)
    }
}
```

`FolderArt/ContentViewModel.swift` と `FolderArtTests/ContentViewModelTests.swift` を削除。

`FolderArt/ContentView.swift` を **暫定の最小版** に書き換える (Task 19 で完成形にする):

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        VStack {
            Text("FolderArt").font(.headline)
            Text("画面は再構築中")
        }
        .frame(minWidth: 760, minHeight: 720)
    }
}
```

- [ ] **Step 4: テスト**

Run: `xcodegen generate` → テスト実行 (全体)
Expected: AppModelTests 3 PASS。全体 PASS。

- [ ] **Step 5: コミット**

```bash
git add -A FolderArt/AppModel.swift FolderArt/ContentViewModel.swift FolderArt/ContentView.swift FolderArtTests/ContentViewModelTests.swift FolderArtTests/AppModelTests.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "refactor: ♻️ ContentViewModel を AppModel + FolderSelection/OverlayState/ApplyCoordinator に分割"
```

---

### Task 14: DropZoneView の複数 URL 対応と DropReceiver の再利用化

**Files:**
- Modify: `FolderArt/Views/DropZoneView.swift`

**Interfaces:**
- Produces:
  - `struct DropZoneView` の `onDropURL: (URL) -> Void` を `onDropURLs: ([URL]) -> Void` に変更。`Mode` は `.folder` / `.image` のまま。
  - `struct FileDropReceiver: NSViewRepresentable { init(isTargeted: Binding<Bool>, accepts: @escaping ([URL]) -> Bool, onDrop: @escaping ([URL]) -> Void) }` を **internal** で公開 (Task 15 の FolderListView と Task 19 のウィンドウ全体ドロップが使う)。
- UI のみのタスクなので自動テストは無し。Step 3 でビルドと手動確認。

- [ ] **Step 1: 実装**

`FolderArt/Views/DropZoneView.swift` の 106 行目以降 (`AppKitDropReceiver` と `DropReceiverNSView`) を次に置き換え、`DropZoneView` 側は `onDropURL` を `onDropURLs: ([URL]) -> Void` に改名し、`.overlay(AppKitDropReceiver(...))` を次に変える:

```swift
        .overlay(
            FileDropReceiver(
                isTargeted: $isTargeted,
                accepts: { urls in
                    switch mode {
                    case .folder: return urls.contains(where: Self.isDirectory)
                    case .image:  return urls.contains(where: Self.isImage)
                    }
                },
                onDrop: { urls in
                    switch mode {
                    case .folder: onDropURLs(urls.filter(Self.isDirectory))
                    case .image:  onDropURLs(urls.filter(Self.isImage))
                    }
                }
            )
        )
```

`DropZoneView` に static ヘルパを足す:

```swift
    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
    }
```

新しい受け口 (同ファイル末尾):

```swift
// MARK: - AppKit D&D レシーバー (再利用可能)

/// SwiftUI の onDrop は macOS で信頼性が低いため、NSView で .fileURL を受ける。
/// クリックは透過させる (hitTest = nil) ので、下のボタン操作を妨げない。
struct FileDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let accepts: ([URL]) -> Bool
    let onDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> DropReceiverNSView {
        let view = DropReceiverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropReceiverNSView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator {
        var parent: FileDropReceiver
        init(_ parent: FileDropReceiver) { self.parent = parent }

        func accepts(_ urls: [URL]) -> Bool { parent.accepts(urls) }
        func setTargeted(_ value: Bool) { DispatchQueue.main.async { self.parent.isTargeted = value } }
        func handle(_ urls: [URL]) { DispatchQueue.main.async { self.parent.onDrop(urls) } }
    }
}

final class DropReceiverNSView: NSView {
    var coordinator: FileDropReceiver.Coordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = validate(sender)
        coordinator?.setTargeted(valid)
        return valid ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validate(sender) ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { coordinator?.setTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { coordinator?.setTargeted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator?.setTargeted(false)
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, coordinator?.accepts(urls) == true else { return false }
        coordinator?.handle(urls)
        return true
    }

    private func validate(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        return !urls.isEmpty && (coordinator?.accepts(urls) ?? false)
    }

    /// ドロップされた **全件** の file URL
    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            .flatMap { $0 as? [URL] } ?? []
    }
}
```

- [ ] **Step 2: ビルド**

Run: `xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' -quiet 2>&1 | grep -E "error:|BUILD"`
Expected: エラーなし (ContentView は暫定版なので DropZoneView はまだ使われていないが、コンパイルは通る)

- [ ] **Step 3: コミット**

```bash
git add FolderArt/Views/DropZoneView.swift
git commit -m "refactor: ♻️ ドロップ受け口を FileDropReceiver に切り出し複数 URL を受け取る"
```

---

### Task 15: FolderListView

**Files:**
- Create: `FolderArt/Views/FolderListView.swift`

**Interfaces:**
- Consumes: `FolderSelection`, `FileDropReceiver`, `DropZoneView.isDirectory`
- Produces: `struct FolderListView: View { @ObservedObject var selection: FolderSelection; let onAdd: () -> Void; let onDropFolders: ([URL]) -> Void }`

- [ ] **Step 1: 実装**

`FolderArt/Views/FolderListView.swift`:

```swift
import SwiftUI

/// 適用先フォルダのリスト。全体がドロップ先。行は複数選択可 (選択があればその分だけに適用)。
struct FolderListView: View {
    @ObservedObject var selection: FolderSelection
    let onAdd: () -> Void
    let onDropFolders: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("フォルダー (\(selection.folders.count))")
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
                if !selection.selectedIDs.isEmpty {
                    Button("選択解除") { selection.clearSelection() }
                        .buttonStyle(.borderless).font(.caption)
                }
                Button { onAdd() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(Text("フォルダーを追加…"))
            }

            if selection.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text("フォルダーをここにドロップ")
                        .font(.callout).foregroundColor(.secondary)
                    Button("フォルダーを選択…", action: onAdd).buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection.folders, id: \.self, selection: $selection.selectedIDs) { url in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { selection.remove(url) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundColor(.secondary)
                            .help(Text("リストから外す"))
                    }
                    .help(Text(url.path))
                }
                .listStyle(.inset)
                .onExitCommand { selection.clearSelection() }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
        .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.accentColor.opacity(0.05) : .clear))
        .overlay(
            FileDropReceiver(
                isTargeted: $isTargeted,
                accepts: { $0.contains(where: DropZoneView.isDirectory) },
                onDrop: { onDropFolders($0.filter(DropZoneView.isDirectory)) }
            )
        )
    }
}
```

- [ ] **Step 2: ビルド**

Run: `xcodegen generate` → `xcodebuild build … | grep -E "error:|BUILD"`
Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add FolderArt/Views/FolderListView.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ FolderListView を追加 (複数フォルダのリストと行選択)"
```

---

### Task 16: OverlayPickerView と SymbolGridView (4 タブ)

**Files:**
- Create: `FolderArt/Views/SymbolGridView.swift`
- Create: `FolderArt/Views/OverlayPickerView.swift`

**Interfaces:**
- Consumes: `OverlayState`, `SymbolCatalog`, `DropZoneView`, `AssetStore.image(for:)`
- Produces:
  - `struct SymbolGridView: View { let catalog: SymbolCatalog; @Binding var selected: String? }`
  - `struct OverlayPickerView: View { @ObservedObject var state: OverlayState; let catalog: SymbolCatalog; let onPickImage: () -> Void; let onDropImage: (URL) -> Void }`
  - `extension OverlayState.Tab { var title: LocalizedStringKey }`

- [ ] **Step 1: 実装**

`FolderArt/Views/SymbolGridView.swift`:

```swift
import SwiftUI

/// 記号タブの中身: 検索欄 + グリッド。
struct SymbolGridView: View {
    let catalog: SymbolCatalog
    @Binding var selected: String?

    @State private var query = ""
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8)

    var body: some View {
        VStack(spacing: 6) {
            TextField("検索 (folder, star, camera…)", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(catalog.search(query), id: \.self) { name in
                        Button { selected = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selected == name ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(selected == name ? Color.accentColor : .clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(Text(name))
                    }
                }
                .padding(2)
            }
            if let selected {
                Text(selected).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
    }
}
```

`FolderArt/Views/OverlayPickerView.swift`:

```swift
import SwiftUI
import AppKit

extension OverlayState.Tab {
    var title: LocalizedStringKey {
        switch self {
        case .image:  return "画像"
        case .symbol: return "記号"
        case .emoji:  return "絵文字"
        case .text:   return "文字"
        }
    }
}

/// 「何を重ねるか」を選ぶ 4 タブ。設定スライダーとプレビューは 4 種類で共通。
struct OverlayPickerView: View {
    @ObservedObject var state: OverlayState
    let catalog: SymbolCatalog
    let onPickImage: () -> Void
    let onDropImage: (URL) -> Void

    var body: some View {
        VStack(spacing: 8) {
            Picker("", selection: $state.activeTab) {
                ForEach(OverlayState.Tab.allCases) { tab in
                    Text(tab.title).tag(tab)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            switch state.activeTab {
            case .image:
                DropZoneView(
                    mode: .image,
                    selectedURL: state.imageAssetID.map { state.assets.url(for: $0) },
                    previewImage: state.imageAssetID.flatMap { state.assets.image(for: $0) },
                    onDropURLs: { urls in if let first = urls.first { onDropImage(first) } },
                    onTapButton: onPickImage
                )
            case .symbol:
                SymbolGridView(catalog: catalog, selected: $state.symbolName)
            case .emoji:
                VStack(spacing: 8) {
                    TextField("絵文字を入力", text: $state.emoji)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 28))
                        .multilineTextAlignment(.center)
                        .onChange(of: state.emoji) { value in
                            // 1 文字 (1 書記素) に制限
                            if value.count > 1 { state.emoji = String(value.suffix(1)) }
                        }
                    Button {
                        NSApp.orderFrontCharacterPalette(nil)
                    } label: {
                        Label("絵文字パレットを開く", systemImage: "face.smiling")
                    }
                    .buttonStyle(.borderless)
                    Text("Ctrl + Cmd + Space でも開けます").font(.caption).foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .text:
                VStack(spacing: 8) {
                    TextField("文字を入力 (例: 2026, A, 案)", text: $state.text)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 20))
                        .multilineTextAlignment(.center)
                    Text("長い文字は自動で縮小されます。2〜4 文字が読みやすい大きさです。")
                        .font(.caption).foregroundColor(.secondary).multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.secondary.opacity(0.06)))
    }
}
```

`DropZoneView` の画像タブでの `selectedURL` はファイル名表示にしか使わないので、AssetStore の URL (UUID 名) をそのまま渡すと UUID が表示される。`DropZoneView` の 77〜84 行目のファイル名表示を、`mode == .image` のときは出さないように変える:

```swift
            if let url = displayURL, mode == .folder {
```

- [ ] **Step 2: ビルド**

Run: `xcodegen generate` → `xcodebuild build … | grep -E "error:|BUILD"`
Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add FolderArt/Views/SymbolGridView.swift FolderArt/Views/OverlayPickerView.swift FolderArt/Views/DropZoneView.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ OverlayPickerView (画像/記号/絵文字/文字の 4 タブ) を追加"
```

---

### Task 17: PresetStripView と ControlsView の更新

**Files:**
- Create: `FolderArt/Views/PresetStripView.swift`
- Modify: `FolderArt/Views/ControlsView.swift`

**Interfaces:**
- Consumes: `PresetStore`, `OverlayRenderer`, `IconComposer`, `AssetStore`
- Produces:
  - `struct PresetStripView: View { @ObservedObject var store: PresetStore; let assets: AssetStore; let canSave: Bool; let onSave: () -> Void; let onApply: (Preset) -> Void; let onRename: (Preset, String) -> Void; let onRemove: (Preset) -> Void }`
  - `ControlsView` に `showsTint: Bool` を追加 (画像タブでは色の行を無効表示)

- [ ] **Step 1: PresetStripView を実装**

`FolderArt/Views/PresetStripView.swift`:

```swift
import SwiftUI

/// お気に入りの帯。チップはサムネイル、クリックで復元、右クリックで名前変更・削除。
struct PresetStripView: View {
    @ObservedObject var store: PresetStore
    let assets: AssetStore
    let canSave: Bool
    let onSave: () -> Void
    let onApply: (Preset) -> Void
    let onRename: (Preset, String) -> Void
    let onRemove: (Preset) -> Void

    @State private var renaming: Preset?
    @State private var newName = ""

    var body: some View {
        HStack(spacing: 8) {
            Text("お気に入り").font(.callout).foregroundColor(.secondary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(store.presets) { preset in
                        PresetChip(preset: preset, assets: assets)
                            .onTapGesture { onApply(preset) }
                            .contextMenu {
                                Button("名前を変更…") { newName = preset.name; renaming = preset }
                                Button("削除", role: .destructive) { onRemove(preset) }
                            }
                            .help(Text(preset.name))
                    }
                    if store.presets.isEmpty {
                        Text("★ を押すと今の見た目を保存できます").font(.caption).foregroundColor(.secondary)
                    }
                }
            }

            Button { onSave() } label: { Image(systemName: "star") }
                .buttonStyle(.borderless)
                .disabled(!canSave)
                .help(Text("今の見た目をお気に入りに保存"))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .sheet(item: $renaming) { preset in
            VStack(spacing: 12) {
                Text("お気に入りの名前").font(.headline)
                TextField("名前", text: $newName).textFieldStyle(.roundedBorder).frame(width: 240)
                HStack {
                    Button("キャンセル") { renaming = nil }.keyboardShortcut(.cancelAction)
                    Button("保存") { onRename(preset, newName); renaming = nil }
                        .keyboardShortcut(.defaultAction).disabled(newName.isEmpty)
                }
            }
            .padding(20)
        }
    }
}

private struct PresetChip: View {
    let preset: Preset
    let assets: AssetStore

    var body: some View {
        Group {
            if let thumb = thumbnail {
                Image(nsImage: thumb).resizable().scaledToFit()
            } else {
                Image(systemName: "questionmark.square.dashed").foregroundColor(.secondary)
            }
        }
        .frame(width: 40, height: 40)
        .padding(3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.1)))
    }

    /// 64px で合成した小さなサムネイル
    private var thumbnail: NSImage? {
        guard let rendered = OverlayRenderer.render(preset.overlay, settings: preset.settings, side: 128, assets: assets),
              let composed = IconComposer.compose(overlay: rendered, settings: preset.settings) else { return nil }
        return composed
    }
}
```

サムネイルは表示のたびに合成すると重いので、`PresetChip` で `@State private var cached: NSImage?` を持ち、`.task(id: preset.id) { cached = thumbnail }` で 1 回だけ作る形にする (`body` では `cached` を使う)。

- [ ] **Step 2: ControlsView を更新**

`FolderArt/Views/ControlsView.swift` を丸ごと置き換え:

```swift
import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings
    /// 画像タブでは色は効かないので無効表示にする
    var showsTint: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("配置:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker("", selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            SliderRow(label: "サイズ:", value: $settings.scale, range: 0.2...1.0,
                      format: { "\(Int($0 * 100))%" })
                .disabled(settings.clipToFolderShape && settings.position == .center)
                .opacity(settings.clipToFolderShape && settings.position == .center ? 0.4 : 1.0)

            SliderRow(label: "不透明度:", value: $settings.opacity, range: 0.1...1.0,
                      format: { "\(Int($0 * 100))%" })

            SliderRow(label: "上下位置:", value: $settings.verticalOffset, range: -0.4...0.4,
                      format: { v in
                          if abs(v) < 0.01 { return String(localized: "中央") }
                          return v > 0 ? String(localized: "上\(Int(v * 100))%") : String(localized: "下\(Int(-v * 100))%")
                      })

            HStack {
                Text("色:").font(.callout).frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: tintBinding, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!showsTint)
                    .opacity(showsTint ? 1 : 0.4)
                Text(showsTint ? "記号と文字に適用" : "画像には適用されません")
                    .font(.caption).foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Text("").frame(width: 80, alignment: .trailing)
                // 表示名を内部名 (clipToFolderShape) と一致させる
                Toggle("フォルダー形に切り抜く", isOn: $settings.clipToFolderShape)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal)
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.tintColor.nsColor) },
            set: { settings.tintColor = CodableColor(NSColor($0)) }
        )
    }
}

private struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label).font(.callout).frame(width: 80, alignment: .trailing)
            Slider(value: $value, in: range)
            Text(format(value)).font(.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}
```

- [ ] **Step 3: ビルド**

Run: `xcodegen generate` → `xcodebuild build … | grep -E "error:|BUILD"`
Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
git add FolderArt/Views/PresetStripView.swift FolderArt/Views/ControlsView.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ お気に入りの帯 (PresetStripView) と色の設定行を追加"
```

---

### Task 18: PreviewView (hover 拡大 + 実寸列)

**Files:**
- Create: `FolderArt/Views/PreviewView.swift`

**Interfaces:**
- Produces: `struct PreviewView: View { let image: NSImage?; let placeholder: LocalizedStringKey }`

- [ ] **Step 1: 実装**

`FolderArt/Views/PreviewView.swift`:

```swift
import SwiftUI

/// 128px のプレビュー。hover でレイアウトを動かさずに拡大版と実寸列を上に重ねる。
struct PreviewView: View {
    let image: NSImage?
    let placeholder: LocalizedStringKey

    @State private var hovering = false
    private let sizes: [CGFloat] = [16, 32, 64, 128]

    var body: some View {
        VStack(spacing: 8) {
            Text("プレビュー").font(.caption).foregroundColor(.secondary)
            ZStack {
                if let image {
                    Image(nsImage: image).resizable().scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 128, height: 128)
                        .overlay(Text(placeholder).font(.caption).foregroundColor(.secondary)
                                    .multilineTextAlignment(.center))
                }
            }
            .onHover { hovering = $0 && image != nil }
            .overlay(alignment: .center) {
                if hovering, let image {
                    VStack(spacing: 10) {
                        Image(nsImage: image).resizable().scaledToFit()
                            .frame(width: 256, height: 256)
                        HStack(alignment: .bottom, spacing: 14) {
                            ForEach(sizes, id: \.self) { side in
                                VStack(spacing: 2) {
                                    Image(nsImage: image).resizable().interpolation(.high)
                                        .frame(width: side, height: side)
                                    Text("\(Int(side))").font(.system(size: 9)).foregroundColor(.secondary)
                                }
                            }
                        }
                        Text("Finder での見え方 (px)").font(.caption2).foregroundColor(.secondary)
                    }
                    .padding(16)
                    .background(RoundedRectangle(cornerRadius: 14).fill(.regularMaterial).shadow(radius: 12))
                    .transition(.opacity.combined(with: .scale(scale: 0.9)))
                    .allowsHitTesting(false)
                }
            }
            .zIndex(10)
            .animation(.easeOut(duration: 0.15), value: hovering)
        }
    }
}
```

- [ ] **Step 2: ビルド**

Run: `xcodegen generate` → `xcodebuild build … | grep -E "error:|BUILD"`
Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add FolderArt/Views/PreviewView.swift FolderArt.xcodeproj/project.pbxproj
git commit -m "feat: ✨ PreviewView を追加 (hover で拡大と 16/32/64/128px の実寸列)"
```

---

### Task 19: ContentView の組み立て、HistoryView v2、ウィンドウ設定

**Files:**
- Modify: `FolderArt/ContentView.swift` (完成形)
- Modify: `FolderArt/Views/HistoryView.swift`
- Modify: `FolderArt/FolderArtApp.swift`

**Interfaces:**
- Consumes: Task 13〜18 のすべて

- [ ] **Step 1: ContentView を書く**

`FolderArt/ContentView.swift`:

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var model: AppModel
    // 入れ子の ObservableObject の変更で再描画させるため、同じインスタンスを ObservedObject でも持つ
    @ObservedObject private var overlayState: OverlayState
    @ObservedObject private var folderSelection: FolderSelection
    @State private var catalog = SymbolCatalog.load()
    @State private var showHistory = false
    @State private var showError = false
    @State private var windowTargeted = false

    init() {
        let m = AppModel()
        _model = StateObject(wrappedValue: m)
        _overlayState = ObservedObject(wrappedValue: m.overlay)
        _folderSelection = ObservedObject(wrappedValue: m.folders)
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()

            HStack(alignment: .top, spacing: 12) {
                FolderListView(
                    selection: model.folders,
                    onAdd: { model.selectFoldersWithPanel() },
                    onDropFolders: { model.addFolders($0) }
                )
                .frame(minWidth: 240)

                OverlayPickerView(
                    state: model.overlay,
                    catalog: catalog,
                    onPickImage: { model.selectImageWithPanel() },
                    onDropImage: { model.selectImage($0) }
                )
                .frame(minWidth: 380)
            }
            .frame(height: 260)
            .padding(12)

            PresetStripView(
                store: model.presets,
                assets: model.assets,
                canSave: overlayState.overlay != nil,
                onSave: { model.saveCurrentAsPreset() },
                onApply: { model.applyPreset($0) },
                onRename: { model.renamePreset($0, to: $1) },
                onRemove: { model.removePreset($0) }
            )
            Divider()

            HStack(alignment: .top, spacing: 12) {
                ControlsView(settings: $overlayState.settings,
                             showsTint: overlayState.activeTab != .image)
                    .frame(maxWidth: .infinity)
                PreviewView(image: overlayState.previewImage,
                            placeholder: "フォルダーと\n重ねるものを選択")
                    .frame(width: 200)
            }
            .padding(.vertical, 12)
            Divider()

            actionBar
        }
        .frame(minWidth: 760, minHeight: 720)
        .overlay(
            // ウィンドウのどこに落としてもフォルダ/画像を振り分ける (内側の受け口が優先される)
            FileDropReceiver(
                isTargeted: $windowTargeted,
                accepts: { $0.contains { DropZoneView.isDirectory($0) || DropZoneView.isImage($0) } },
                onDrop: { model.handleDroppedURLs($0) }
            )
        )
        .sheet(isPresented: $showHistory) {
            HistoryView(historyStore: model.history) { task in
                model.reset(task: task)
                showHistory = false
            }
        }
        .onChange(of: model.errorMessage) { msg in showError = (msg != nil) }
        .alert("お知らせ", isPresented: $showError) {
            Button("OK") { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    private var toolbar: some View {
        HStack {
            Text("FolderArt").font(.headline)
            Spacer()
            Button { showHistory = true } label: { Label("履歴", systemImage: "clock") }
                .buttonStyle(.borderless)
        }
        .padding(.horizontal).padding(.vertical, 10)
    }

    private var actionBar: some View {
        HStack {
            Button { model.resetTargets() } label: { Label("リセット", systemImage: "arrow.uturn.backward") }
                .disabled(folderSelection.isEmpty || model.isApplying)
                .help(Text("適用先のフォルダーのアイコンを元に戻す"))

            Button { folderSelection.removeAll() } label: { Label("リストを空にする", systemImage: "xmark.bin") }
                .disabled(folderSelection.isEmpty || model.isApplying)

            Spacer()

            if let p = model.progress {
                Text("\(p.done) / \(p.total)").font(.callout).monospacedDigit().foregroundColor(.secondary)
            }

            Button { Task { await model.apply() } } label: {
                Label(model.applyButtonTitle, systemImage: "checkmark.circle.fill")
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canApply)
            .keyboardShortcut(.defaultAction)
        }
        .padding()
    }
}
```

`canApply` と `applyButtonTitle` は `AppModel` の計算プロパティで、`overlayState` / `folderSelection` の変更で `ContentView` が再評価されるので、そのまま `model.canApply` / `model.applyButtonTitle` を参照してよい。

- [ ] **Step 2: HistoryView を v2 対応**

`FolderArt/Views/HistoryView.swift` 39〜49 行目:

```swift
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: task.folderPath).lastPathComponent)
                                    .font(.body).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("\(task.overlay.displayName) · \(task.settings.position.displayName)")
                                    if !task.overlay.canReapply {
                                        Text("(旧形式)").foregroundColor(.orange)
                                    }
                                }
                                .font(.caption).foregroundColor(.secondary)
                                Text(dateFormatter.string(from: task.appliedAt))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
```

`.frame(width: 400, height: 360)` は `.frame(minWidth: 440, minHeight: 360)` に変える。

- [ ] **Step 3: ウィンドウ設定**

`FolderArt/FolderArtApp.swift`:

```swift
import SwiftUI

@main
struct FolderArtApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 720)
    }
}
```

- [ ] **Step 4: ビルドと全テスト**

Run: テスト実行 (全体)
Expected: BUILD OK、全テスト PASS

- [ ] **Step 5: 手動確認 (アプリを起動して)**

Run: `xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' -derivedDataPath build -quiet && open build/Build/Products/Debug/FolderArt.app`

確認項目 (すべて満たすこと):
1. フォルダを 3 つまとめて左のリストにドロップ → 3 行表示。同じフォルダをもう一度落としても増えない。
2. 「記号」タブで `star` を検索して選ぶ → プレビューに白い星。色を赤に変える → 星が赤になる。
3. 「文字」タブに `2026` → プレビューに文字。空にするとプレビューが消え、適用ボタンが無効。
4. 「絵文字」タブでパレットから 1 つ選ぶ → プレビューに出る。
5. ウィンドウの余白に PNG を落とす → 「画像」タブに切り替わり画像が入る。
6. 「3 フォルダに適用」→ Finder で 3 つとも変わる。履歴に 3 行。
7. リストで 1 行だけ選ぶ → ボタンが「選択した 1 フォルダに適用」。別の記号で適用 → その 1 つだけ変わり、履歴は 3 行のまま。
8. ★ で保存 → 帯にチップ。別タブに移ってからチップをクリック → 元のタブと設定に戻る。右クリックで名前変更と削除ができる。
9. プレビューに hover → 拡大版と 16/32/64/128 の列が上に重なり、隣のスライダーは動かない。
10. 「リセット」→ 適用先のアイコンが標準に戻る。履歴からのリセットも動く。
11. 存在しないフォルダ (適用前に Finder で消す) を含めて適用 → 「2 件成功、1 件失敗」のアラート。成功分はそのまま。

- [ ] **Step 6: コミット**

```bash
git add FolderArt/ContentView.swift FolderArt/Views/HistoryView.swift FolderArt/FolderArtApp.swift
git commit -m "feat: ✨ 新しい画面構成に組み替え (フォルダリスト・4 タブ・お気に入り・hover プレビュー)"
```

---

### Task 20: バージョン、README、最終確認

**Files:**
- Modify: `project.yml` (MARKETING_VERSION 1.1.0、CURRENT_PROJECT_VERSION 3)
- Modify: `README.md` (機能一覧を日英併記で更新)

- [ ] **Step 1: バージョン**

`project.yml`:

```yaml
        MARKETING_VERSION: 1.1.0
        CURRENT_PROJECT_VERSION: 3
```

`xcodegen generate` を実行。

- [ ] **Step 2: README の機能一覧を更新**

`README.md` の機能一覧 (30〜36 行目付近) を、日本語と英語の両方で次の項目に置き換える:

- 重ねるものを 4 種類から選択: 画像 / SF Symbols (制限付き記号は除外) / 絵文字 / 文字 — Overlay sources: image, SF Symbols (restricted symbols excluded), emoji, text
- 記号と文字の色を指定 — Tint color for symbols and text
- お気に入り: 見た目 (オーバーレイ + 設定) を保存し 1 クリックで復元 — Presets: save a look and restore it in one click
- 複数フォルダへの一括適用、行を選べば一部だけに再適用 — Batch apply to many folders; select rows to re-apply to a subset
- プレビューに hover で拡大表示と 16/32/64/128px の実寸 — Hover the preview to enlarge it and see 16/32/64/128px renderings
- ドラッグ&ドロップ (複数フォルダ、ウィンドウ任意位置への画像) — Drag & drop (multiple folders, images anywhere in the window)
- 位置・サイズ・不透明度・上下位置・フォルダ形切り抜き — Position, size, opacity, vertical offset, clip to folder shape
- バックアップ、リセット、履歴 — Backup, reset, history

README に SF Symbols の扱いを 1 段落追加する (日英):
「SF Symbols は macOS の実行時 API で描画しており、画像ファイルは同梱していません。Apple 製品や機能を表す制限付き記号は選択肢から除外しています。」

- [ ] **Step 3: 全テストとビルド**

Run: テスト実行 (全体)
Expected: 全 PASS。警告があれば内容を確認し、strict concurrency 由来の警告以外は直す。

- [ ] **Step 4: コミット**

```bash
git add project.yml FolderArt.xcodeproj/project.pbxproj README.md
git commit -m "chore: 🔖 1.1.0 に更新し README の機能一覧を日英で更新"
```

- [ ] **Step 5: 仕上げ**

`@codex-rescue` をフォアグラウンドで回してから PR を作る (CLAUDE.md の流儀)。PR 本文は日英併記。PR 作成後は codex レビューの指摘が尽きるまで対応し、`develop` にマージ後 `main` を同じ位置に進める。
