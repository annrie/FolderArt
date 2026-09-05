# FolderArt 第4段階 実装計画: 上下位置の既定値、お気に入りの一部書き出し、ユーザー辞書、文言チェックの実物照合

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 起動直後の上下位置がフォルダ本体の見た目の中心になり、お気に入りを選んで `.folderartpack` に書き出せ、自分の提案辞書を JSON で足せて保存すると即反映され、文言カタログをコンパイラ抽出の実物と突き合わせられる FolderArt 1.5.0 を作る。

**Architecture:** 上下位置は `CompositionSettings.verticalOffset` の既定値を −0.04 に変えるだけで、`IconComposer.folderBodyCenterOffset(of:)` (純関数) が OS のアイコンから実測した値との差を見張りテストで監視する。一部書き出しは純粋な値型 `PresetExportSelection` を状態に持つ `PresetExportPickerView` (popover) が選んだ `[Preset]` を `AppModel.exportPack(presets:)` に渡し、既存の `PackWriter` で書く。ユーザー辞書は `SuggestionDictionary.loadUser(at:)` (正規化・整理・上限) と `merging(user:bundled:)` で同梱辞書と合成し、`FileWatcher` (ディレクトリ + ファイルの vnode 監視) の通知で `AppModel.reloadUserDictionary()` が世代付きで読み直して `SuggestionEngine` を差し替える。文言チェックは `build-xcstrings.py --stringsdata` が `.stringsdata` の実物キーと `strings.json` を厳密比較する。

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 13.0+, XcodeGen 2.46, XCTest, DispatchSource (vnode), CryptoKit (SHA-256)、Python 3。

**Spec:** `docs/superpowers/specs/2026-09-06-center-partial-export-userdict-design.md`

## Global Constraints

- deploymentTarget macOS 13.0、SWIFT_VERSION 5.9。macOS 14 以降専用 API は使わない (`@Observable` 不可、`onChange(of:initial:)` 不可、`onChange(of:) { value in }` の 1 引数形を使う)。
- 新しいファイルを追加したら `xcodegen generate` を実行し、`FolderArt.xcodeproj/project.pbxproj` の差分もコミットに含める。`scripts/` 配下はビルドに入らない。
- **`xcodebuild` は必ずフォアグラウンドで `timeout: 600000` を付けて実行する。バックグラウンド実行 (`run_in_background`) は使わない** (完了通知が届かず停滞する)。
- テスト実行コマンド (以後「テスト実行」):
  ```bash
  xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"
  ```
  1 クラスだけ走らせるときは `-only-testing:FolderArtTests/<ClassName>` を足す。プロジェクト由来の `warning:` は 0 件を保つ (`appintentsmetadataprocessor …`、`ld: warning`、`ContentScannerTests` が意図的に出す `*** ERROR: CGImageSourceCreateThumbnailAtIndex … failed` は環境由来で無視)。
- テストはアプリ自身をホストとしてサンドボックス内で走る。一時ファイルは `FileManager.default.temporaryDirectory` 配下に作る。`HistoryStore.appSupportDirectory` (実アプリのデータ) をテストから触らない (ユーザー辞書の URL は init で注入する)。
- UI 文言はすべて `Text("…")` (自動で `LocalizedStringKey`) か `String(localized:)`。**新しい文言を足したら `scripts/localization/strings.json` に 8 言語分の行 (順: ja, en, de, es, fr, ko, pt-BR, zh-Hant。ja の値はキーと同じ) を足し、`python3 scripts/localization/build-xcstrings.py` で `Localizable.xcstrings` を作り直してコミットに含める。** `python3 scripts/localization/build-xcstrings.py --check` が `missing: 0` であること。キーの形は Swift の補間から抽出される形 (`Int` は `%lld`、`String` は `%@`)。単複の variation は値を `one||other` で書き、ja / ko / zh-Hant は 1 形。
- 新しい依存パッケージは追加しない。
- コミットメッセージは既存の流儀 (`feat: ✨ …`, `fix: 🐛 …`, `refactor: ♻️ …`, `test: ✅ …`, `docs: 📝 …`, `chore: 🔧 …` + 日本語) に合わせ、末尾に次を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- ブランチは `feature/center-partial-export-userdict` (作成済み、`develop` = `main` = v1.4.0 (2b88cff) から分岐)。main / develop には直接コミットしない。
- 既存の 247 テストは維持する (既定値の変更に伴う期待値の更新を除く)。

## File Structure

```
FolderArt/
├── AppModel.swift                     変更: exportPack(presets:) / exportPack(to:presets:)、ユーザー辞書 (注入・reload・監視・エラー)、revealUserDictionary
├── FolderArtApp.swift                 変更: 「提案辞書を開く…」(通知を post)
├── ContentView.swift                  変更: onExportSelected の配線、revealUserDictionaryNotification の受け口
├── Models/
│   ├── CompositionSettings.swift      変更: verticalOffset の既定値 −0.04
│   └── PresetExportSelection.swift    新規: 選択状態の値型
├── Services/
│   ├── IconComposer.swift             変更: folderBodyCenterOffset(of:side:)
│   ├── SuggestionDictionary.swift     変更: UserDictionaryError、loadUser(at:)、normalizedUser(_:)、merging(user:bundled:)
│   └── FileWatcher.swift              新規: ディレクトリ + ファイルの vnode 監視
├── Views/
│   ├── PresetStripView.swift          変更: 「選んで書き出す…」、popover、PresetChip を internal に
│   └── PresetExportPickerView.swift   新規: チェックリストの popover
scripts/localization/
├── build-xcstrings.py                 変更: --stringsdata モード
├── check-compiled.sh                  新規: SWIFT_EMIT_LOC_STRINGS=YES でビルドして --stringsdata
└── strings.json                       変更: 文言の追加 (Localizable.xcstrings を再生成)
FolderArtTests/
├── IconComposerTests.swift            変更: 本体中心の固定図形テストと OS の見張りテスト
├── CompositionSettingsTests.swift     変更: 既定値の期待値
├── PresetExportSelectionTests.swift   新規
├── AppModelTests.swift                変更: defer、部分書き出し、ユーザー辞書、監視、起動時エラーの連結
├── SuggestionDictionaryTests.swift    変更: loadUser / merging
└── FileWatcherTests.swift             新規
project.yml                            変更: 1.5.0 / ビルド 8
README.md                              変更: 使い方、提案辞書のカスタマイズ、構成、注意
```

---

### Task 1: 上下位置の既定値 −0.04 と本体中心の実測 (+ 走査テストの defer)

**Files:**
- Modify: `FolderArt/Models/CompositionSettings.swift:7`
- Modify: `FolderArt/Services/IconComposer.swift` (関数を 1 つ追加)
- Modify: `FolderArtTests/IconComposerTests.swift` (2 件追加)
- Modify: `FolderArtTests/CompositionSettingsTests.swift` (既定値の期待値)
- Modify: `FolderArtTests/AppModelTests.swift` (ゲートの `defer`)

**Interfaces:**
- Produces: `CompositionSettings().verticalOffset == -0.04`、`IconComposer.folderBodyCenterOffset(of image: NSImage, side: Int = 512) -> Double?` (下が正。アイコン高さに対する比)。

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/IconComposerTests.swift` のクラス末尾に追加:

```swift
    // MARK: - フォルダ本体の中心

    /// 蓋 (幅 40% × 高さ 10%) + 本体 (幅 100% × 高さ 70%) の合成図形。本体は y = 20%…90% なので中心は 55%、
    /// 正方形の中央 (50%) より 5% 下 → +0.05
    private func makeFolderLikeShape(side: Int) -> NSImage {
        let s = CGFloat(side)
        return BitmapCanvas.draw(size: CGSize(width: s, height: s)) { _ in
            NSColor.blue.setFill()
            // NSGraphicsContext は左下原点。蓋は上から 10%…20% = 下から 80%…90%
            NSRect(x: 0, y: s * 0.80, width: s * 0.40, height: s * 0.10).fill()
            // 本体は上から 20%…90% = 下から 10%…80%
            NSRect(x: 0, y: s * 0.10, width: s, height: s * 0.70).fill()
        }!
    }

    func testFolderBodyCenterOffsetOnFixture() throws {
        let offset = try XCTUnwrap(IconComposer.folderBodyCenterOffset(of: makeFolderLikeShape(side: 100), side: 100))
        XCTAssertEqual(offset, 0.05, accuracy: 0.011)   // 1 画素分 (0.01) の丸めを許す
        XCTAssertNil(IconComposer.folderBodyCenterOffset(of: NSImage(size: NSSize(width: 10, height: 10)), side: 10))   // 不透明な画素が無い
    }

    /// 環境依存の見張り: 起動中の macOS の標準フォルダアイコンで実測した本体中心と、既定の上下位置が一致すること。
    /// Apple がフォルダの形を変えた macOS で落ちる。そのときはメッセージの実測値で既定値を測り直す
    func testDefaultVerticalOffsetMatchesFolderBodyCenter() throws {
        let measured = try XCTUnwrap(IconComposer.folderBodyCenterOffset(of: IconComposer.standardFolderIcon))
        let expected = -CompositionSettings().verticalOffset
        XCTAssertEqual(measured, expected, accuracy: 0.015,
                       "本体の中心は正方形の中央より \(measured * 100)% 下 (既定値は \(expected * 100)%)。既定値を測り直してください")
    }
```

`FolderArtTests/CompositionSettingsTests.swift`: 既定値を見ている箇所を −0.04 に合わせる。具体的には、`CompositionSettings()` と JSON の往復や `decodeIfPresent` の既定を比べているテスト (26 行目付近の `"verticalOffset":0.0` を含む JSON を使うもの) は、JSON 側を `"verticalOffset":-0.04` にするか、期待値を `CompositionSettings().verticalOffset` にする。`XCTAssertEqual(…verticalOffset, 0)` の形があれば `-0.04` に。変更した箇所を報告に列挙する。

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/IconComposerTests`)
Expected: コンパイルエラー (`folderBodyCenterOffset` が無い)

- [ ] **Step 3: 既定値を変える**

`FolderArt/Models/CompositionSettings.swift`:

```swift
    /// 上下位置 (−0.4 … 0.4、上が正)。既定は「下4%」: 標準フォルダアイコンは蓋の分だけ本体が下に寄っているので、
    /// 正方形の中央に置くと少し上に見える。本体 (蓋を除く) の中心は macOS 15.7 の実測で正方形の中央より 4.0% 下
    /// (IconComposer.folderBodyCenterOffset(of:) を参照。IconComposerTests の見張りテストが OS の変化を知らせる)。
    /// 保存済みの設定は自分の値を持つので変わらない
    var verticalOffset: Double = -0.04   // -0.4 ... 0.4 (上:正, 下:負)
```

- [ ] **Step 4: 実測の関数**

`FolderArt/Services/IconComposer.swift` の `standardFolderIcon` の直後に追加:

```swift
    /// フォルダアイコンの「本体」(蓋を除く) の中心が正方形の中央からどれだけ下にあるか (アイコンの高さに対する比、下が正)。
    /// 不透明 (alpha > 0.5) な画素が行の最大幅の 90% 以上ある行を本体とみなす (蓋は幅が狭い)。不透明な行が無ければ nil。
    /// CompositionSettings.verticalOffset の既定値はこの値の符号を反転したもの (macOS 15.7 で 0.040)
    static func folderBodyCenterOffset(of image: NSImage, side: Int = 512) -> Double? {
        guard side > 0,
              let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: side, pixelsHigh: side,
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                         colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
              let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = context
        image.draw(in: NSRect(x: 0, y: 0, width: side, height: side), from: .zero, operation: .sourceOver, fraction: 1)
        NSGraphicsContext.restoreGraphicsState()

        // 行ごとの不透明な画素の数 (NSBitmapImageRep の y は上から)
        var widths: [Int] = []
        widths.reserveCapacity(side)
        for y in 0..<side {
            var n = 0
            for x in 0..<side where (rep.colorAt(x: x, y: y)?.alphaComponent ?? 0) > 0.5 { n += 1 }
            widths.append(n)
        }
        guard let maxWidth = widths.max(), maxWidth > 0 else { return nil }
        let threshold = Int((Double(maxWidth) * 0.9).rounded(.up))
        let bodyRows = widths.enumerated().filter { $0.element >= threshold }.map(\.offset)
        guard let top = bodyRows.first, let bottom = bodyRows.last else { return nil }
        let center = Double(top + bottom) / 2 + 0.5   // 画素の中心
        return (center - Double(side) / 2) / Double(side)
    }
```

- [ ] **Step 5: 走査テストのゲートを defer で解放する**

`FolderArtTests/AppModelTests.swift` の「中身の走査」テストのうち `DispatchSemaphore` を作るもの (`testStaleScanResultIsDiscardedWhenSourceChanges`、`testScanResultIsDroppedWhenListBecomesEmpty`、`testReturningToCachedFolderDuringScanCancelsAndAllowsRescan`) で、ゲートを作った直後に `defer { gate.signal() }` を足す (途中で `waitUntil` が throw しても足止め中の背景スレッドを解放する。テスト終了後の余分な permit は無害)。既存の `gate.signal()` 呼び出しはそのまま残す。

- [ ] **Step 6: テスト**

Run: テスト実行 (`-only-testing:FolderArtTests/IconComposerTests -only-testing:FolderArtTests/CompositionSettingsTests -only-testing:FolderArtTests/AppModelTests`)
Expected: 全 PASS。見張りテストが落ちたらメッセージの実測値を報告し、既定値は変えずに BLOCKED で報告する (この Mac では 0.040 のはず)。

Run: テスト実行 (全体)
Expected: `Executed 249 tests, with 0 failures` (247 + 2)、警告 0

- [ ] **Step 7: コミット**

```bash
git add FolderArt/Models/CompositionSettings.swift FolderArt/Services/IconComposer.swift FolderArtTests/IconComposerTests.swift FolderArtTests/CompositionSettingsTests.swift FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ 上下位置の既定を下4% (フォルダ本体の中心) にし、OS のアイコンから実測する見張りテストを追加"
```

---

### Task 2: PresetExportSelection (選択状態の値型)

**Files:**
- Create: `FolderArt/Models/PresetExportSelection.swift`
- Test: `FolderArtTests/PresetExportSelectionTests.swift`

**Interfaces:**
- Consumes: `Preset` (既存。`id: UUID`)
- Produces: `struct PresetExportSelection: Equatable { private(set) var selectedIDs: Set<UUID>; mutating func toggle(_:); mutating func selectAll(_:); mutating func clear(); func isSelected(_:) -> Bool; func selected(from:) -> [Preset]; mutating func prune(to:) }`

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/PresetExportSelectionTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class PresetExportSelectionTests: XCTestCase {
    private let a = Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())
    private let b = Preset(name: "b", overlay: .text("b"), settings: CompositionSettings())
    private let c = Preset(name: "c", overlay: .text("c"), settings: CompositionSettings())

    func testToggleFlips() {
        var s = PresetExportSelection()
        XCTAssertFalse(s.isSelected(a.id))
        s.toggle(a.id)
        XCTAssertTrue(s.isSelected(a.id))
        s.toggle(a.id)
        XCTAssertFalse(s.isSelected(a.id))
    }

    func testSelectAllAndClear() {
        var s = PresetExportSelection()
        s.selectAll([a, b, c])
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "b", "c"])
        s.clear()
        XCTAssertTrue(s.selected(from: [a, b, c]).isEmpty)
    }

    func testSelectedKeepsStripOrderAndIgnoresUnknownIDs() {
        var s = PresetExportSelection()
        s.toggle(c.id); s.toggle(a.id)
        s.toggle(UUID())   // 存在しない ID
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "c"])
        XCTAssertEqual(s.selected(from: [c, b, a]).map(\.name), ["c", "a"])
    }

    func testPruneDropsIDsNoLongerPresent() {
        var s = PresetExportSelection()
        s.selectAll([a, b, c])
        s.prune(to: [a, c])
        XCTAssertEqual(s.selectedIDs, [a.id, c.id])
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "c"])
    }
}
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/PresetExportSelectionTests`)
Expected: コンパイルエラー

- [ ] **Step 3: 実装**

`FolderArt/Models/PresetExportSelection.swift`:

```swift
import Foundation

/// 「選んで書き出す」の選択状態。お気に入りのリストは持たず ID だけを持つ純粋な値型。
/// 件数や書き出す配列は常に今のお気に入り (`selected(from:)`) から数える。初期状態は未選択
struct PresetExportSelection: Equatable {
    private(set) var selectedIDs: Set<UUID> = []

    mutating func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    mutating func selectAll(_ presets: [Preset]) {
        selectedIDs = Set(presets.map(\.id))
    }

    mutating func clear() {
        selectedIDs = []
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    /// 帯の順を保つ。今のお気に入りに無い ID は無視する
    func selected(from presets: [Preset]) -> [Preset] {
        presets.filter { selectedIDs.contains($0.id) }
    }

    /// お気に入りが増減したら呼ぶ。今のお気に入りに無い ID を捨てる
    mutating func prune(to presets: [Preset]) {
        selectedIDs.formIntersection(presets.map(\.id))
    }
}
```

- [ ] **Step 4: xcodegen とテスト**

```bash
xcodegen generate
```

Run: テスト実行 (`-only-testing:FolderArtTests/PresetExportSelectionTests`)
Expected: 4 tests PASS

Run: テスト実行 (全体)
Expected: `Executed 253 tests, with 0 failures`、警告 0

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Models/PresetExportSelection.swift FolderArt.xcodeproj/project.pbxproj FolderArtTests/PresetExportSelectionTests.swift
git commit -m "feat: ✨ お気に入りの一部書き出し用の選択状態 (PresetExportSelection) を追加"
```

---

### Task 3: 「選んで書き出す…」(popover) と AppModel.exportPack(presets:)

**Files:**
- Modify: `FolderArt/AppModel.swift:394-420` (`exportPack` 系)
- Modify: `FolderArt/Views/PresetStripView.swift` (メニュー項目、popover、`PresetChip` を internal に、`onExportSelected`)
- Create: `FolderArt/Views/PresetExportPickerView.swift`
- Modify: `FolderArt/ContentView.swift:43-54` (`onExportSelected` の配線)
- Modify: `scripts/localization/strings.json` (+4 キー) → `FolderArt/Resources/Localizable.xcstrings` を再生成
- Test: `FolderArtTests/AppModelTests.swift` (2 件追加)

**Interfaces:**
- Consumes: Task 2 の `PresetExportSelection`、既存の `PackWriter.write(_:assets:appVersion:)`、`PresetStore.presets`
- Produces: `AppModel.exportPack()` (全件、変更なし)、`AppModel.exportPack(presets: [Preset])` (NSSavePanel)、`AppModel.exportPack(to url: URL, presets: [Preset]? = nil)`、`PresetStripView(... onExport:onImport:onExportSelected:)`、`PresetExportPickerView(store:assets:onExport:)`

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/AppModelTests.swift` の「お気に入り」まわりに追加 (既存の `testExportAndImportPackRoundTrip` の近く):

```swift
    func testExportPackSubsetWritesOnlySelected() throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        try model.presets.add(name: "月", overlay: .symbol(name: "moon.fill"), settings: CompositionSettings())
        let moon = try XCTUnwrap(model.presets.presets.first { $0.name == "月" })
        let file = root.appendingPathComponent("subset.folderartpack")
        model.exportPack(to: file, presets: [moon])
        XCTAssertNil(model.errorMessage)
        let pack = try PackReader.read(try Data(contentsOf: file))
        XCTAssertEqual(pack.presets.map(\.name), ["月"])
    }

    func testExportPackEmptySubsetExplainsAndWritesNothing() throws {
        try model.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let file = root.appendingPathComponent("empty.folderartpack")
        model.exportPack(to: file, presets: [])
        XCTAssertEqual(model.errorMessage, String(localized: "書き出せるお気に入りがありません。"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: コンパイルエラー (`exportPack(to:presets:)` が無い)

- [ ] **Step 3: AppModel**

`FolderArt/AppModel.swift` の `exportPack()` と `exportPack(to:)` を次に置き換える:

```swift
    /// お気に入り全部を 1 ファイルに書き出す (NSSavePanel)
    func exportPack() {
        exportPack(presets: presets.presets)
    }

    /// 選んだお気に入りだけを 1 ファイルに書き出す (NSSavePanel)。空なら理由を伝えて戻る
    func exportPack(presets selected: [Preset]) {
        guard !isApplying else { return }
        // ファイルメニューからは常に選べるので、帯の「…」と違って黙って戻らず理由を伝える
        guard !selected.isEmpty else {
            errorMessage = String(localized: "書き出せるお気に入りがありません。")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.packType]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = String(localized: "FolderArt-お気に入り-\(formatter.string(from: Date())).folderartpack")
        panel.prompt = String(localized: "書き出す")
        if panel.runModal() == .OK, let url = panel.url { exportPack(to: url, presets: selected) }
    }

    /// presets を省略すれば全件。空なら書かずに理由を伝える (NSSavePanel を通らない経路も同じ判定を通す)
    func exportPack(to url: URL, presets selected: [Preset]? = nil) {
        guard !isApplying else { return }
        let toWrite = selected ?? presets.presets
        guard !toWrite.isEmpty else {
            errorMessage = String(localized: "書き出せるお気に入りがありません。")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try PackWriter.write(toWrite, assets: assets, appVersion: appVersion)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "パックを書き出せませんでした: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: popover のビュー**

`FolderArt/Views/PresetExportPickerView.swift`:

```swift
import SwiftUI

/// 「選んで書き出す」の popover。チェックリストで選んだお気に入りだけを onExport に渡す。
/// 選択は ID だけを持ち、件数と書き出す配列は常に今のお気に入りから数える (表示中に削除されても食い違わない)
struct PresetExportPickerView: View {
    @ObservedObject var store: PresetStore
    let assets: AssetStore
    let onExport: ([Preset]) -> Void

    @State private var selection = PresetExportSelection()

    private var selectedPresets: [Preset] { selection.selected(from: store.presets) }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("お気に入りを選んで書き出す").font(.headline)
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(store.presets) { preset in
                        Toggle(isOn: Binding(
                            get: { selection.isSelected(preset.id) },
                            set: { _ in selection.toggle(preset.id) }
                        )) {
                            HStack(spacing: 8) {
                                PresetChip(preset: preset, assets: assets)
                                Text(preset.name).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        .toggleStyle(.checkbox)
                    }
                }
                .padding(.vertical, 2)
            }
            .frame(maxHeight: 320)
            HStack {
                Button("すべて選択") { selection.selectAll(store.presets) }
                Button("選択解除") { selection.clear() }
                    .disabled(selectedPresets.isEmpty)
                Spacer()
                Button { onExport(selectedPresets) } label: {
                    Text("書き出す (\(selectedPresets.count) 件)")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(selectedPresets.isEmpty)
            }
        }
        .padding(12)
        .frame(width: 300)
        // 表示中にお気に入りが削除・読み込み・並び替えされたら、無くなった ID を捨てる
        .onChange(of: store.presets) { presets in selection.prune(to: presets) }
    }
}
```

- [ ] **Step 5: PresetStripView**

`FolderArt/Views/PresetStripView.swift`:

1. プロパティに `let onExportSelected: ([Preset]) -> Void` を `onImport` の次に追加し、`@State private var showsExportPicker = false` を `newName` の次に追加。
2. 「…」の `Menu` を次に置き換える:

```swift
            Menu {
                Button("パックを書き出す…") { onExport() }
                    .disabled(store.presets.isEmpty || isApplying)
                Button("選んで書き出す…") {
                    // メニューが閉じてから popover を出す (同じ操作の中で dismiss と presentation を競合させない)
                    DispatchQueue.main.async { showsExportPicker = true }
                }
                .disabled(store.presets.isEmpty || isApplying)
                Button("パックを読み込む…") { onImport() }
                    .disabled(isApplying)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .frame(width: 28)
            .help(Text("お気に入りのパックを書き出す / 読み込む"))
            .popover(isPresented: $showsExportPicker, arrowEdge: .bottom) {
                PresetExportPickerView(store: store, assets: assets) { selected in
                    showsExportPicker = false
                    onExportSelected(selected)
                }
            }
```

3. `private struct PresetChip: View` の `private` を外して `struct PresetChip: View` にする (popover から流用)。

- [ ] **Step 6: ContentView の配線**

`FolderArt/ContentView.swift` の `PresetStripView(...)` の引数に、`onImport: { model.importPackWithPanel() }` の次の行として追加:

```swift
                onExportSelected: { model.exportPack(presets: $0) }
```

(`onImport` の行末にカンマを足す)

- [ ] **Step 7: 文言**

`scripts/localization/strings.json` に 4 行を追加 (順は ja, en, de, es, fr, ko, pt-BR, zh-Hant):

```json
  "選んで書き出す…": ["選んで書き出す…", "Export Selected…", "Auswahl exportieren…", "Exportar seleccionados…", "Exporter la sélection…", "선택해서 내보내기…", "Exportar selecionados…", "選擇後匯出…"],
  "お気に入りを選んで書き出す": ["お気に入りを選んで書き出す", "Choose presets to export", "Vorlagen zum Exportieren auswählen", "Elige los favoritos que quieres exportar", "Choisissez les favoris à exporter", "내보낼 즐겨찾기 선택", "Escolha os favoritos para exportar", "選擇要匯出的收藏"],
  "すべて選択": ["すべて選択", "Select All", "Alle auswählen", "Seleccionar todo", "Tout sélectionner", "모두 선택", "Selecionar tudo", "全選"],
  "書き出す (%lld 件)": ["書き出す (%lld 件)", "Export (%lld item)||Export (%lld items)", "Exportieren (%lld Objekt)||Exportieren (%lld Objekte)", "Exportar (%lld elemento)||Exportar (%lld elementos)", "Exporter (%lld élément)||Exporter (%lld éléments)", "내보내기 (%lld개)", "Exportar (%lld item)||Exportar (%lld itens)", "匯出（%lld 個）"]
```

```bash
python3 scripts/localization/build-xcstrings.py
python3 scripts/localization/build-xcstrings.py --check
xcodegen generate
```

Expected: `--check` の最終行が `missing: 0`。

- [ ] **Step 8: テストとビルド**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests -only-testing:FolderArtTests/LocalizationTests`)
Expected: 全 PASS (`LocalizationTests` は 4 キーが 8 言語とも入っていることを確かめる)

Run: テスト実行 (全体)
Expected: `Executed 255 tests, with 0 failures`、警告 0

Debug ビルド (`xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -configuration Debug -destination 'platform=macOS' -derivedDataPath build 2>&1 | grep -E "error:|warning:|BUILD (SUCCEEDED|FAILED)" | grep -v "ld: warning"`): `BUILD SUCCEEDED`。実機 (popover の出方、Esc / クリック外で閉じる、0 件で無効、2 件中 1 件を書き出して読み戻す) はコントローラーが行う。

- [ ] **Step 9: コミット**

```bash
git add FolderArt/AppModel.swift FolderArt/Views/PresetStripView.swift FolderArt/Views/PresetExportPickerView.swift FolderArt/ContentView.swift scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArt.xcodeproj/project.pbxproj FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ お気に入りを選んで .folderartpack に書き出せるようにする (帯の「…」からチェックリストの popover)"
```

---

### Task 4: ユーザー辞書の読み込み (loadUser) と同梱辞書との合成 (merging)

**Files:**
- Modify: `FolderArt/Services/SuggestionDictionary.swift`
- Modify: `scripts/localization/strings.json` (+7 キー) → `Localizable.xcstrings` を再生成
- Test: `FolderArtTests/SuggestionDictionaryTests.swift` (追加)

**Interfaces:**
- Consumes: `SuggestionEntry`、`PackReader.withinLimit(_:graphemes:)` (既存)
- Produces:
  - `enum UserDictionaryError: LocalizedError, Equatable { case tooLarge(Int), tooManyEntries(Int), tooManyKeys(Int), keyTooLong(String), symbolTooLong(String), emojiTooLong(String), malformed(String) }`
  - `SuggestionDictionary.userFileName = "suggestions-user.json"`、上限の定数 (`userMaxFileBytes` 1 MB、`userMaxEntries` 1000、`userMaxKeysPerEntry` 50、`userMaxKeyLength` 64、`userMaxSymbolLength` 100、`userMaxEmojiLength` 8)
  - `static func loadUser(at url: URL) -> Result<SuggestionDictionary, Error>?` (無ければ nil)
  - `static func normalizedUser(_ raw: [SuggestionEntry]) throws -> SuggestionDictionary` (正規化・整理・上限。loadUser の中身、テスト用に公開)
  - `static func merging(user: SuggestionDictionary, bundled: SuggestionDictionary) -> SuggestionDictionary`
  - `static let userTemplate: String` (「提案辞書を開く…」が作る雛形の JSON 文字列)

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/SuggestionDictionaryTests.swift` に追加:

```swift
    // MARK: - ユーザー辞書

    private func entry(_ keys: [String], symbol: String? = "star.fill", emoji: String? = "⭐") -> SuggestionEntry {
        SuggestionEntry(keys: keys, symbol: symbol, emoji: emoji)
    }

    private func write(_ json: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("SuggestionDictionaryTests_\(UUID().uuidString).json")
        try json.write(to: url, atomically: true, encoding: .utf8)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    func testMergingUserWinsAndBundledLosesOverriddenKeys() {
        let bundled = SuggestionDictionary(entries: [
            entry(["photo", "photos"], symbol: "photo.fill", emoji: "📷"),
            entry(["music"], symbol: "music.note", emoji: "🎵"),
        ])
        let user = SuggestionDictionary(entries: [entry(["photo", "pics"], symbol: "camera.fill", emoji: "📸")])
        let merged = SuggestionDictionary.merging(user: user, bundled: bundled)
        XCTAssertEqual(merged.entries.count, 3)
        XCTAssertEqual(merged.entries[0].keys, ["photo", "pics"])          // ユーザーが先頭
        XCTAssertEqual(merged.entries[1].keys, ["photos"])                 // 同梱から photo が外れる
        XCTAssertEqual(merged.entries[2].keys, ["music"])                  // 無関係な項目はそのまま
        XCTAssertEqual(merged.entry(forKey: "photo")?.symbol, "camera.fill")
        // 合成後もキーは 1 項目にしか現れない
        let all = merged.entries.flatMap(\.keys)
        XCTAssertEqual(all.count, Set(all).count)
    }

    func testMergingDropsBundledEntriesLeftWithoutKeys() {
        let bundled = SuggestionDictionary(entries: [entry(["pdf"], symbol: "doc.richtext.fill", emoji: "📄")])
        let user = SuggestionDictionary(entries: [entry(["pdf"], symbol: "doc.fill", emoji: nil)])
        let merged = SuggestionDictionary.merging(user: user, bundled: bundled)
        XCTAssertEqual(merged.entries.map(\.keys), [["pdf"]])
        XCTAssertEqual(merged.entries[0].symbol, "doc.fill")
    }

    func testMergingWithEmptyUserIsBundled() {
        let bundled = SuggestionDictionary(entries: [entry(["a"]), entry(["b"])])
        XCTAssertEqual(SuggestionDictionary.merging(user: .empty, bundled: bundled), bundled)
    }

    func testLoadUserReturnsNilWhenAbsent() {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("no-such-\(UUID().uuidString).json")
        XCTAssertNil(SuggestionDictionary.loadUser(at: url))
    }

    func testLoadUserMalformedIsFailure() throws {
        let url = try write("{ not json")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.malformed = error else { return XCTFail("expected malformed, got \(error)") }
    }

    func testLoadUserNormalizesKeysAndDedupes() throws {
        let url = try write("""
        [
          {"keys": ["Ｐｈｏｔｏ", " photo ", "PHOTO", "", "旅行"], "symbol": "camera.fill", "emoji": ""},
          {"keys": ["photo", "trip"], "symbol": "", "emoji": "✈️"},
          {"keys": ["nothing"], "symbol": "", "emoji": ""},
          {"keys": ["   "], "symbol": "star.fill"}
        ]
        """)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected success") }
        XCTAssertEqual(dict.entries.count, 2)
        XCTAssertEqual(dict.entries[0].keys, ["photo", "旅行"])      // 全角→半角、小文字化、前後の空白、重複、空を整理
        XCTAssertEqual(dict.entries[0].symbol, "camera.fill")
        XCTAssertNil(dict.entries[0].emoji)                        // 空文字は nil
        XCTAssertEqual(dict.entries[1].keys, ["trip"])             // 項目間の重複は先勝ち
        XCTAssertEqual(dict.entries[1].emoji, "✈️")
        XCTAssertNil(dict.entries[1].symbol)
        // "nothing" は symbol も emoji も無いので捨てる、"   " はキーが空になるので捨てる
    }

    func testLoadUserRejectsOversizedInput() throws {
        let many = (0..<(SuggestionDictionary.userMaxEntries + 1)).map { #"{"keys": ["k\#($0)"], "emoji": "⭐"}"# }.joined(separator: ",")
        let url = try write("[\(many)]")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        XCTAssertEqual(error as? UserDictionaryError, .tooManyEntries(SuggestionDictionary.userMaxEntries + 1))

        let longKey = String(repeating: "a", count: SuggestionDictionary.userMaxKeyLength + 1)
        let url2 = try write(#"[{"keys": ["\#(longKey)"], "emoji": "⭐"}]"#)
        guard case .failure(let error2)? = SuggestionDictionary.loadUser(at: url2) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.keyTooLong = error2 else { return XCTFail("expected keyTooLong, got \(error2)") }

        let manyKeys = (0..<(SuggestionDictionary.userMaxKeysPerEntry + 1)).map { "\"k\($0)\"" }.joined(separator: ",")
        let url3 = try write(#"[{"keys": [\#(manyKeys)], "emoji": "⭐"}]"#)
        guard case .failure(let error3)? = SuggestionDictionary.loadUser(at: url3) else { return XCTFail("expected failure") }
        XCTAssertEqual(error3 as? UserDictionaryError, .tooManyKeys(SuggestionDictionary.userMaxKeysPerEntry + 1))
    }

    func testLoadUserRejectsFileOverOneMegabyte() throws {
        // 1 MB + 1 バイトの JSON (空白で水増し)。読む前にサイズで弾く
        let padding = String(repeating: " ", count: SuggestionDictionary.userMaxFileBytes + 1)
        let url = try write("[\(padding)]")
        guard case .failure(let error)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("expected failure") }
        guard case UserDictionaryError.tooLarge = error else { return XCTFail("expected tooLarge, got \(error)") }
    }

    func testUserTemplateIsValidAndLoadable() throws {
        let url = try write(SuggestionDictionary.userTemplate)
        guard case .success(let dict)? = SuggestionDictionary.loadUser(at: url) else { return XCTFail("template must load") }
        XCTAssertEqual(dict.entries.count, 1)
        XCTAssertEqual(dict.entries[0].keys, ["example", "サンプル"])
    }

    func testUserDictionaryErrorsAreLocalized() {
        for error in [UserDictionaryError.tooLarge(1), .tooManyEntries(2), .tooManyKeys(3), .keyTooLong("k"), .symbolTooLong("s"), .emojiTooLong("e"), .malformed("m")] {
            XCTAssertFalse(error.localizedDescription.isEmpty, "\(error)")
        }
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionDictionaryTests`)
Expected: コンパイルエラー

- [ ] **Step 3: 実装**

`FolderArt/Services/SuggestionDictionary.swift` の末尾に追加:

```swift
/// ユーザー辞書 (suggestions-user.json) の読み込みで起きる失敗。文言はアラート「提案辞書を読めません: …」の後ろに付く
enum UserDictionaryError: LocalizedError, Equatable {
    case tooLarge(Int)
    case tooManyEntries(Int)
    case tooManyKeys(Int)
    case keyTooLong(String)
    case symbolTooLong(String)
    case emojiTooLong(String)
    case malformed(String)

    var errorDescription: String? {
        switch self {
        case .tooLarge:
            return String(localized: "提案辞書のファイルが大きすぎます (上限 \(SuggestionDictionary.userMaxFileBytes / 1024 / 1024) MB)")
        case .tooManyEntries(let n):
            return String(localized: "提案辞書の項目が多すぎます (\(n) 件、上限 \(SuggestionDictionary.userMaxEntries) 件)")
        case .tooManyKeys(let n):
            return String(localized: "提案辞書の 1 項目のキーが多すぎます (\(n) 個、上限 \(SuggestionDictionary.userMaxKeysPerEntry) 個)")
        case .keyTooLong(let key):
            return String(localized: "提案辞書のキーが長すぎます: \(key)")
        case .symbolTooLong(let symbol):
            return String(localized: "提案辞書の記号名が長すぎます: \(symbol)")
        case .emojiTooLong(let emoji):
            return String(localized: "提案辞書の絵文字が長すぎます: \(emoji)")
        case .malformed(let reason):
            return String(localized: "提案辞書の JSON の形式が違います: \(reason)")
        }
    }
}

extension SuggestionDictionary {
    static let userFileName = "suggestions-user.json"
    static let userMaxFileBytes = 1 * 1024 * 1024
    static let userMaxEntries = 1000
    static let userMaxKeysPerEntry = 50
    static let userMaxKeyLength = 64
    static let userMaxSymbolLength = 100
    static let userMaxEmojiLength = 8

    /// 「提案辞書を開く…」がファイルを作るときの雛形 (例を 1 件)
    static let userTemplate = """
    [
      {"keys": ["example", "サンプル"], "symbol": "star.fill", "emoji": "⭐"}
    ]

    """

    /// ユーザー辞書を読む。無ければ nil、読めない・形式が違う・上限超えなら .failure。
    /// 成功側は正規化と整理 (normalizedUser) を済ませてある。メインの外から呼んでよい (ファイル I/O)
    static func loadUser(at url: URL) -> Result<SuggestionDictionary, Error>? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        do {
            // 復号の前にサイズで弾く (巨大なファイルを丸ごとメモリに載せない)
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            if let size = attributes[.size] as? Int, size > userMaxFileBytes { throw UserDictionaryError.tooLarge(size) }
            let data = try Data(contentsOf: url)
            guard data.count <= userMaxFileBytes else { throw UserDictionaryError.tooLarge(data.count) }
            let raw: [SuggestionEntry]
            do {
                raw = try JSONDecoder().decode([SuggestionEntry].self, from: data)
            } catch {
                throw UserDictionaryError.malformed(error.localizedDescription)
            }
            return .success(try normalizedUser(raw))
        } catch {
            return .failure(error)
        }
    }

    /// ユーザー辞書の項目を整える。順に:
    /// 1. キーを NFKC + 小文字化し前後の空白を落とす。空になったキーは捨てる。項目内の重複は 1 つにまとめる
    /// 2. 項目間で同じキーは先の項目が勝ち、後の項目から外す
    /// 3. symbol / emoji の空文字は nil 扱い。両方 nil の項目は捨てる
    /// 4. キーが無くなった項目は捨てる
    /// 上限 (ファイルサイズは loadUser で、項目数・キー数・長さはここで) を超えれば throw する。
    /// 日本語キーの「2 文字以上」の規則はユーザー辞書には課さない
    static func normalizedUser(_ raw: [SuggestionEntry]) throws -> SuggestionDictionary {
        guard raw.count <= userMaxEntries else { throw UserDictionaryError.tooManyEntries(raw.count) }
        var seen = Set<String>()
        var entries: [SuggestionEntry] = []
        for entry in raw {
            guard entry.keys.count <= userMaxKeysPerEntry else { throw UserDictionaryError.tooManyKeys(entry.keys.count) }
            var keys: [String] = []
            for rawKey in entry.keys {
                let key = rawKey.precomposedStringWithCompatibilityMapping.lowercased()
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                guard !key.isEmpty else { continue }
                guard PackReader.withinLimit(key, graphemes: userMaxKeyLength) else {
                    throw UserDictionaryError.keyTooLong(String(key.prefix(userMaxKeyLength)))
                }
                guard !keys.contains(key), !seen.contains(key) else { continue }
                keys.append(key)
            }
            let symbol = entry.symbol.flatMap { $0.isEmpty ? nil : $0 }
            let emoji = entry.emoji.flatMap { $0.isEmpty ? nil : $0 }
            if let symbol, !PackReader.withinLimit(symbol, graphemes: userMaxSymbolLength) {
                throw UserDictionaryError.symbolTooLong(String(symbol.prefix(userMaxSymbolLength)))
            }
            if let emoji, !PackReader.withinLimit(emoji, graphemes: userMaxEmojiLength) {
                throw UserDictionaryError.emojiTooLong(String(emoji.prefix(userMaxEmojiLength)))
            }
            guard !keys.isEmpty, symbol != nil || emoji != nil else { continue }
            seen.formUnion(keys)
            entries.append(SuggestionEntry(keys: keys, symbol: symbol, emoji: emoji))
        }
        return SuggestionDictionary(entries: entries)
    }

    /// ユーザー辞書の項目を先頭に置き、同じキーを持つ同梱項目からはそのキーを外す。キーが無くなった同梱項目は捨てる。
    /// user は normalizedUser 済み (キーの重複が無い) であること
    static func merging(user: SuggestionDictionary, bundled: SuggestionDictionary) -> SuggestionDictionary {
        let userKeys = Set(user.entries.flatMap(\.keys))
        var entries = user.entries
        for entry in bundled.entries {
            let keys = entry.keys.filter { !userKeys.contains($0) }
            guard !keys.isEmpty else { continue }
            entries.append(SuggestionEntry(keys: keys, symbol: entry.symbol, emoji: entry.emoji))
        }
        return SuggestionDictionary(entries: entries)
    }
}
```

(キーの正規化に `SuggestionEngine.normalize` を使わないのは、あれが camelCase の境界に空白を入れるため (`iPhone` → `i phone`)。辞書のキーは同梱辞書と同じく「小文字の 1 語」なので NFKC + 小文字化だけにする)

- [ ] **Step 4: 文言**

`scripts/localization/strings.json` に 7 行を追加:

```json
  "提案辞書のファイルが大きすぎます (上限 %lld MB)": ["提案辞書のファイルが大きすぎます (上限 %lld MB)", "The suggestion dictionary file is too large (limit %lld MB)", "Die Wörterbuchdatei ist zu groß (Limit %lld MB)", "El archivo del diccionario de sugerencias es demasiado grande (límite %lld MB)", "Le fichier du dictionnaire de suggestions est trop volumineux (limite %lld Mo)", "제안 사전 파일이 너무 큽니다 (최대 %lld MB)", "O arquivo do dicionário de sugestões é grande demais (limite %lld MB)", "建議字典檔案過大（上限 %lld MB）"],
  "提案辞書の項目が多すぎます (%lld 件、上限 %lld 件)": ["提案辞書の項目が多すぎます (%lld 件、上限 %lld 件)", "The suggestion dictionary has too many entries (%lld, limit %lld)", "Das Wörterbuch enthält zu viele Einträge (%lld, Limit %lld)", "El diccionario tiene demasiadas entradas (%lld, límite %lld)", "Le dictionnaire contient trop d’entrées (%lld, limite %lld)", "제안 사전의 항목이 너무 많습니다 (%lld개, 최대 %lld개)", "O dicionário tem entradas demais (%lld, limite %lld)", "建議字典的項目過多（%lld 個，上限 %lld 個）"],
  "提案辞書の 1 項目のキーが多すぎます (%lld 個、上限 %lld 個)": ["提案辞書の 1 項目のキーが多すぎます (%lld 個、上限 %lld 個)", "A dictionary entry has too many keys (%lld, limit %lld)", "Ein Wörterbucheintrag hat zu viele Schlüssel (%lld, Limit %lld)", "Una entrada del diccionario tiene demasiadas claves (%lld, límite %lld)", "Une entrée du dictionnaire a trop de clés (%lld, limite %lld)", "사전 항목의 키가 너무 많습니다 (%lld개, 최대 %lld개)", "Uma entrada do dicionário tem chaves demais (%lld, limite %lld)", "字典的某個項目鍵過多（%lld 個，上限 %lld 個）"],
  "提案辞書のキーが長すぎます: %@": ["提案辞書のキーが長すぎます: %@", "A dictionary key is too long: %@", "Ein Wörterbuchschlüssel ist zu lang: %@", "Una clave del diccionario es demasiado larga: %@", "Une clé du dictionnaire est trop longue : %@", "사전의 키가 너무 깁니다: %@", "Uma chave do dicionário é longa demais: %@", "字典的鍵過長：%@"],
  "提案辞書の記号名が長すぎます: %@": ["提案辞書の記号名が長すぎます: %@", "A dictionary symbol name is too long: %@", "Ein Symbolname im Wörterbuch ist zu lang: %@", "Un nombre de símbolo del diccionario es demasiado largo: %@", "Un nom de symbole du dictionnaire est trop long : %@", "사전의 심볼 이름이 너무 깁니다: %@", "Um nome de símbolo do dicionário é longo demais: %@", "字典的符號名稱過長：%@"],
  "提案辞書の絵文字が長すぎます: %@": ["提案辞書の絵文字が長すぎます: %@", "A dictionary emoji is too long: %@", "Ein Emoji im Wörterbuch ist zu lang: %@", "Un emoji del diccionario es demasiado largo: %@", "Un emoji du dictionnaire est trop long : %@", "사전의 이모지가 너무 깁니다: %@", "Um emoji do dicionário é longo demais: %@", "字典的表情符號過長：%@"],
  "提案辞書の JSON の形式が違います: %@": ["提案辞書の JSON の形式が違います: %@", "The suggestion dictionary is not valid JSON: %@", "Das Wörterbuch ist kein gültiges JSON: %@", "El diccionario no es un JSON válido: %@", "Le dictionnaire n’est pas un JSON valide : %@", "제안 사전의 JSON 형식이 올바르지 않습니다: %@", "O dicionário não é um JSON válido: %@", "建議字典的 JSON 格式不正確：%@"]
```

```bash
python3 scripts/localization/build-xcstrings.py
python3 scripts/localization/build-xcstrings.py --check
```

Expected: `missing: 0`

- [ ] **Step 5: テスト**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionDictionaryTests -only-testing:FolderArtTests/LocalizationTests`)
Expected: 全 PASS (追加 10 件)

Run: テスト実行 (全体)
Expected: `Executed 265 tests, with 0 failures`、警告 0

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Services/SuggestionDictionary.swift scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArtTests/SuggestionDictionaryTests.swift
git commit -m "feat: ✨ ユーザー辞書 (suggestions-user.json) の読み込み・正規化・上限と、同梱辞書との合成を追加"
```

---

### Task 5: FileWatcher (ディレクトリ + ファイルの vnode 監視)

**Files:**
- Create: `FolderArt/Services/FileWatcher.swift`
- Test: `FolderArtTests/FileWatcherTests.swift`

**Interfaces:**
- Produces: `final class FileWatcher { init?(directory: URL, file: URL, debounce: TimeInterval = 0.3, onChange: @escaping () -> Void) }` — ディレクトリが開けなければ nil。変化は debounce でまとめて **メインキュー** で `onChange` を呼ぶ。解放 (deinit) で監視を止める。

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/FileWatcherTests.swift`:

```swift
import XCTest
@testable import FolderArt

final class FileWatcherTests: XCTestCase {
    private var dir: URL!
    private var file: URL { dir.appendingPathComponent("suggestions-user.json") }

    override func setUp() async throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("FileWatcherTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeWatcher(_ expectation: XCTestExpectation) -> FileWatcher? {
        FileWatcher(directory: dir, file: file, debounce: 0.2) { expectation.fulfill() }
    }

    func testCreatingTheFileNotifies() throws {
        let exp = expectation(description: "created")
        let watcher = try XCTUnwrap(makeWatcher(exp))
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        wait(for: [exp], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    /// 多くのエディタの保存: 一時ファイルに書いて改名する (ファイルの実体が入れ替わる)
    func testAtomicSaveNotifies() throws {
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        let exp = expectation(description: "replaced")
        let watcher = try XCTUnwrap(makeWatcher(exp))
        let temp = dir.appendingPathComponent("tmp.json")
        try "[{}]".write(to: temp, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        wait(for: [exp], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    /// その場で切り詰めて書き直す保存 (ディレクトリの項目は変わらない)
    func testInPlaceWriteNotifies() throws {
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        let exp = expectation(description: "written")
        let watcher = try XCTUnwrap(makeWatcher(exp))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("[ ]".utf8))
        try handle.close()
        wait(for: [exp], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    /// 改名で実体が入れ替わった後も、次のその場の書き直しを拾う (開き直しの確認)。通知は 2 回来る
    func testInPlaceWriteAfterAtomicSaveNotifies() throws {
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        let exp = expectation(description: "replaced, then written in place")
        exp.expectedFulfillmentCount = 2
        let watcher = try XCTUnwrap(makeWatcher(exp))
        let temp = dir.appendingPathComponent("tmp.json")
        try "[{}]".write(to: temp, atomically: false, encoding: .utf8)
        _ = try FileManager.default.replaceItemAt(file, withItemAt: temp)
        // 1 回目の通知 (debounce 0.2 秒) が出るのを待ってから、新しい実体をその場で書き直す
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let handle = try FileHandle(forWritingTo: file)
        try handle.truncate(atOffset: 0)
        try handle.write(contentsOf: Data("[ ]".utf8))
        try handle.close()
        wait(for: [exp], timeout: 3)
        withExtendedLifetime(watcher) {}
    }

    func testBurstOfWritesCoalesces() throws {
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        let exp = expectation(description: "once")
        exp.assertForOverFulfill = true
        let watcher = try XCTUnwrap(makeWatcher(exp))
        for i in 0..<5 { try "[\(i)]".write(to: file, atomically: true, encoding: .utf8) }
        wait(for: [exp], timeout: 3)
        // debounce の 2 倍以上待って、余計な 2 回目が来ないことを確かめる (来れば assertForOverFulfill で落ちる)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        withExtendedLifetime(watcher) {}
    }

    func testNoNotificationAfterRelease() throws {
        let exp = expectation(description: "none")
        exp.isInverted = true
        var watcher: FileWatcher? = makeWatcher(exp)
        XCTAssertNotNil(watcher)
        watcher = nil
        try "[]".write(to: file, atomically: false, encoding: .utf8)
        wait(for: [exp], timeout: 0.8)
    }

    func testMissingDirectoryGivesNil() {
        XCTAssertNil(FileWatcher(directory: dir.appendingPathComponent("nope"), file: file) {})
    }
}
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/FileWatcherTests`)
Expected: コンパイルエラー

- [ ] **Step 3: 実装**

`FolderArt/Services/FileWatcher.swift`:

```swift
import Foundation

/// ディレクトリと (あれば) その中の 1 ファイルを vnode で監視し、変化を debounce でまとめてメインキューで知らせる。
/// ディレクトリの監視は作成・改名・削除 (エディタの原子的保存 = 一時ファイルに書いて改名) を、
/// ファイルの監視はその場での書き直し (truncate + write) を捕まえる。削除・改名の後はファイルを開き直す。
/// fd は O_EVTONLY で開き、cancel handler で close する
final class FileWatcher {
    private let file: URL
    private let debounce: TimeInterval
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "FolderArt.FileWatcher")
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// ディレクトリが開けなければ nil (無い間は監視しない)
    init?(directory: URL, file: URL, debounce: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        self.file = file
        self.debounce = debounce
        self.onChange = onChange
        guard let source = Self.makeSource(path: directory.path, mask: .write, queue: queue) else { return nil }
        directorySource = source
        source.setEventHandler { [weak self] in self?.directoryChanged() }
        source.resume()
        queue.sync { watchFileIfPresent() }
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        pending?.cancel()
    }

    private static func makeSource(path: String, mask: DispatchSource.FileSystemEvent,
                                   queue: DispatchQueue) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setCancelHandler { close(fd) }
        return source
    }

    /// queue 上で呼ぶ。ファイルがあれば (開き直して) 監視する。無ければディレクトリの監視だけになる
    private func watchFileIfPresent() {
        fileSource?.cancel()
        fileSource = nil
        guard let source = Self.makeSource(path: file.path,
                                           mask: [.write, .extend, .attrib, .delete, .rename], queue: queue) else { return }
        fileSource = source
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.fileChanged(flags: source.data)
        }
        source.resume()
    }

    private func directoryChanged() {
        watchFileIfPresent()   // 作成・改名で実体が変わったかもしれないので開き直す
        schedule()
    }

    private func fileChanged(flags: DispatchSource.FileSystemEvent) {
        if flags.contains(.delete) || flags.contains(.rename) { watchFileIfPresent() }
        schedule()
    }

    /// 連続した変化を debounce でまとめ、メインキューで 1 回だけ知らせる
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
```

- [ ] **Step 4: xcodegen とテスト**

```bash
xcodegen generate
```

Run: テスト実行 (`-only-testing:FolderArtTests/FileWatcherTests`)
Expected: 7 tests PASS。`testAtomicSaveNotifies` / `testInPlaceWriteAfterAtomicSaveNotifies` が落ちるなら、`replaceItemAt` がディレクトリの `.write` を出しているか (出ているはず) と、開き直しが `directoryChanged` で行われているかを確認する。落ちる場合は原因と観察を報告し、テストを弱めない。

Run: テスト実行 (全体)
Expected: `Executed 272 tests, with 0 failures`、警告 0

- [ ] **Step 5: コミット**

```bash
git add FolderArt/Services/FileWatcher.swift FolderArt.xcodeproj/project.pbxproj FolderArtTests/FileWatcherTests.swift
git commit -m "feat: ✨ FileWatcher を追加 (ディレクトリとファイルを vnode で監視し、原子的保存とその場の書き直しの両方を捕まえる)"
```

---

### Task 6: AppModel のユーザー辞書 (注入・reload・監視・アラート) と「提案辞書を開く…」

**Files:**
- Modify: `FolderArt/AppModel.swift` (init、プロパティ、ユーザー辞書の節)
- Modify: `FolderArt/FolderArtApp.swift` (メニュー項目)
- Modify: `FolderArt/ContentView.swift` (通知の受け口)
- Modify: `scripts/localization/strings.json` (+3 キー) → `Localizable.xcstrings` を再生成
- Test: `FolderArtTests/AppModelTests.swift` (6 件追加)

**Interfaces:**
- Consumes: Task 4 の `SuggestionDictionary.loadUser(at:)` / `merging(user:bundled:)` / `userFileName` / `userTemplate`、Task 5 の `FileWatcher`
- Produces:
  - `AppModel.init(history:presets:assets:dictionary:catalog:userDictionaryURL:contentScanner:runsMaintenance:)` (`suggestionEngine:` 引数は廃止。`dictionary` = 同梱辞書、既定 `SuggestionDictionary.load()`; `catalog` 既定 `SymbolCatalog.shared`; `userDictionaryURL` 既定 `HistoryStore.appSupportDirectory.appendingPathComponent(SuggestionDictionary.userFileName)`)
  - `private(set) var suggestionEngine`、`let userDictionaryURL: URL`
  - `func reloadUserDictionary() async`、`@discardableResult func prepareUserDictionaryFile() throws -> URL`、`func revealUserDictionary()`
  - `static let revealUserDictionaryNotification = Notification.Name("FolderArt.revealUserDictionary")`

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/AppModelTests.swift` のクラス末尾に追加 (既存の `waitUntil` を使う):

```swift
    // MARK: - ユーザー辞書

    private var testDictionary: SuggestionDictionary {
        SuggestionDictionary(entries: [SuggestionEntry(keys: ["photo"], symbol: "photo.fill", emoji: "📷")])
    }

    /// ユーザー辞書の URL を注入したモデル。ディレクトリ (root) は既にあるので init で監視が始まる
    private func makeDictionaryModel(userDictionary: URL) -> AppModel {
        AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("history3.json")),
                 presets: PresetStore(storageURL: root.appendingPathComponent("presets3.json")),
                 assets: AssetStore(directory: root.appendingPathComponent("assets3")),
                 dictionary: testDictionary,
                 catalog: SymbolCatalog.shared,
                 userDictionaryURL: userDictionary,
                 runsMaintenance: false)
    }

    /// (同名のヘルパが既にクラスにあればそれを使い、この定義は足さない)
    private func makeFolder(_ name: String) throws -> URL {
        let url = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func hasSymbol(_ name: String, in m: AppModel) -> Bool {
        m.suggestions.contains { $0.kind == .symbol(name) }
    }

    func testReloadUserDictionaryChangesSuggestions() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("xyzzy")])
        XCTAssertFalse(hasSymbol("star.fill", in: m))
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill", "emoji": "⭐"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(hasSymbol("star.fill", in: m))
        XCTAssertNil(m.errorMessage)
    }

    func testUserDictionaryOverridesBundledKey() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("photo")])
        XCTAssertTrue(hasSymbol("photo.fill", in: m))
        try #"[{"keys": ["photo"], "symbol": "camera.fill", "emoji": "📸"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(hasSymbol("camera.fill", in: m))
        XCTAssertFalse(hasSymbol("photo.fill", in: m))
    }

    func testBrokenUserDictionaryAlertsOncePerContentAndRecovers() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        let prefix = String(localized: "提案辞書を読めません: \("")")
        try "{ broken".write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false, m.errorMessage ?? "nil")
        m.errorMessage = nil
        await m.reloadUserDictionary()          // 同じ内容ではもう出ない
        XCTAssertNil(m.errorMessage)
        try "{ broken again".write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()          // 内容が変われば 1 回出る
        XCTAssertTrue(m.errorMessage?.hasPrefix(prefix) ?? false)
        m.errorMessage = nil
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill"}]"#.write(to: user, atomically: true, encoding: .utf8)
        await m.reloadUserDictionary()          // 直せば黙って復帰する
        XCTAssertNil(m.errorMessage)
        m.addFolders([try makeFolder("xyzzy")])
        XCTAssertTrue(hasSymbol("star.fill", in: m))
    }

    func testPrepareUserDictionaryFileWritesTemplateOnce() throws {
        let user = root.appendingPathComponent("sub/dir/suggestions-user.json")   // ディレクトリごと無い
        let m = makeDictionaryModel(userDictionary: user)
        let url = try m.prepareUserDictionaryFile()
        XCTAssertEqual(url, user)
        XCTAssertEqual(try String(contentsOf: user, encoding: .utf8), SuggestionDictionary.userTemplate)
        try "[]".write(to: user, atomically: true, encoding: .utf8)
        try m.prepareUserDictionaryFile()        // 既にあれば上書きしない
        XCTAssertEqual(try String(contentsOf: user, encoding: .utf8), "[]")
    }

    func testWatcherReloadsUserDictionaryAutomatically() async throws {
        let user = root.appendingPathComponent("suggestions-user.json")
        let m = makeDictionaryModel(userDictionary: user)
        m.addFolders([try makeFolder("xyzzy")])
        try #"[{"keys": ["xyzzy"], "symbol": "star.fill", "emoji": "⭐"}]"#.write(to: user, atomically: true, encoding: .utf8)
        try await waitUntil { self.hasSymbol("star.fill", in: m) }
        XCTAssertTrue(hasSymbol("star.fill", in: m))
    }

    func testStartupErrorsAreJoined() async throws {
        let historyURL = root.appendingPathComponent("history4.json")
        try "{ broken history".write(to: historyURL, atomically: true, encoding: .utf8)
        let user = root.appendingPathComponent("suggestions-user.json")
        try "{ broken dictionary".write(to: user, atomically: true, encoding: .utf8)
        let m = AppModel(history: HistoryStore(storageURL: historyURL),
                         presets: PresetStore(storageURL: root.appendingPathComponent("presets4.json")),
                         assets: AssetStore(directory: root.appendingPathComponent("assets4")),
                         dictionary: testDictionary, catalog: SymbolCatalog.shared,
                         userDictionaryURL: user, runsMaintenance: false)
        let saved = String(localized: "保存データの読み込みに失敗しました: \("")")
        let dict = String(localized: "提案辞書を読めません: \("")")
        XCTAssertTrue(m.errorMessage?.hasPrefix(saved) ?? false)
        try await waitUntil { m.errorMessage?.contains(dict) ?? false }
        XCTAssertTrue(m.errorMessage?.hasPrefix(saved) ?? false)      // 保存データのエラーは残る
        XCTAssertTrue(m.errorMessage?.contains("\n\n") ?? false)      // 空行で連結
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: コンパイルエラー (`dictionary:` 引数などが無い)

- [ ] **Step 3: AppModel**

`FolderArt/AppModel.swift`:

(a) `import CryptoKit` を `import Combine` の下に追加。

(b) プロパティ: `private let suggestionEngine: SuggestionEngine` を次に置き換える:

```swift
    /// 提案エンジン。ユーザー辞書が変わると作り直す
    private(set) var suggestionEngine: SuggestionEngine
    private let bundledDictionary: SuggestionDictionary
    private let catalog: SymbolCatalog
    /// ユーザー辞書 (suggestions-user.json)。テストでは一時ディレクトリを注入する
    let userDictionaryURL: URL
    private var dictionaryWatcher: FileWatcher?
    /// 読み込みの世代。監視の通知が重なっても最後の 1 回の結果だけ採る
    private var dictionaryGeneration = 0
    /// 直近に失敗したユーザー辞書の内容の SHA-256。同じ内容では二度アラートを出さない
    private var lastDictionaryErrorHash: Data?
```

(c) init の引数と代入:

```swift
    init(history: HistoryStore = HistoryStore(),
         presets: PresetStore = PresetStore(),
         assets: AssetStore = AssetStore(),
         dictionary bundledDictionary: SuggestionDictionary = SuggestionDictionary.load(),
         catalog: SymbolCatalog = SymbolCatalog.shared,
         userDictionaryURL: URL = HistoryStore.appSupportDirectory.appendingPathComponent(SuggestionDictionary.userFileName),
         contentScanner: @escaping ContentScannerFunction = { ContentScanner.scan($0) },
         runsMaintenance: Bool = true) {
        self.history = history
        self.presets = presets
        self.assets = assets
        self.bundledDictionary = bundledDictionary
        self.catalog = catalog
        self.userDictionaryURL = userDictionaryURL
        self.suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
        self.scanContents = contentScanner
```

`CombineLatest3` の購読の直後 (`reapAssets()` の前) に追加:

```swift
        // ユーザー辞書: ディレクトリがあれば監視を始め、初回を読む (メインの外で。結果はメインで反映)
        startDictionaryWatcher()
        Task { [weak self] in await self?.reloadUserDictionary() }
```

`suggestionEngine:` 引数を渡しているテストがあれば (`grep -rn "suggestionEngine:" FolderArtTests`)、`dictionary:` / `catalog:` に書き換える。

(d) 「提案」の節の末尾 (`applySuggestion` の後) に追加:

```swift
    // MARK: - ユーザー辞書

    static let revealUserDictionaryNotification = Notification.Name("FolderArt.revealUserDictionary")

    /// ユーザー辞書を読み直して提案エンジンを差し替える。読み込みと復号はメインの外、差し替えはメイン。
    /// 世代番号で古い結果を捨てる (監視の通知が重なっても最後の 1 回だけ採る)。中身の走査結果は使い回す
    func reloadUserDictionary() async {
        dictionaryGeneration += 1
        let generation = dictionaryGeneration
        let url = userDictionaryURL
        let loaded = await Task.detached(priority: .utility) { () -> (result: Result<SuggestionDictionary, Error>?, hash: Data?) in
            let result = SuggestionDictionary.loadUser(at: url)
            // 失敗したときだけ、同じ内容で二度アラートを出さないための指紋を取る
            var hash: Data?
            if case .failure = result, let data = try? Data(contentsOf: url) { hash = Data(SHA256.hash(data: data)) }
            return (result, hash)
        }.value
        guard generation == dictionaryGeneration else { return }

        switch loaded.result {
        case nil:
            suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
            lastDictionaryErrorHash = nil
        case .success(let user):
            suggestionEngine = SuggestionEngine(dictionary: .merging(user: user, bundled: bundledDictionary), catalog: catalog)
            lastDictionaryErrorHash = nil
        case .failure(let error):
            suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
            if loaded.hash != lastDictionaryErrorHash {
                lastDictionaryErrorHash = loaded.hash
                report(String(localized: "提案辞書を読めません: \(error.localizedDescription)"))
            }
        }
        refreshSuggestions(folders: folders.folders, selectedIDs: folders.selectedIDs, presets: presets.presets)
    }

    /// 既に出ているアラート (起動時の保存データのエラーなど) があれば、その後ろに空行を挟んで連結する
    private func report(_ message: String) {
        if let current = errorMessage, !current.isEmpty {
            errorMessage = current + "\n\n" + message
        } else {
            errorMessage = message
        }
    }

    /// ディレクトリがあるときだけ監視する (無い間は「提案辞書を開く…」で作ったときに始める)。通知のたびに必ず読み直す
    private func startDictionaryWatcher() {
        guard dictionaryWatcher == nil else { return }
        let directory = userDictionaryURL.deletingLastPathComponent()
        dictionaryWatcher = FileWatcher(directory: directory, file: userDictionaryURL) { [weak self] in
            Task { [weak self] in await self?.reloadUserDictionary() }
        }
    }

    /// ユーザー辞書のファイルを (無ければディレクトリごと作って雛形で) 用意し、監視を始める。Finder 表示はしない
    @discardableResult
    func prepareUserDictionaryFile() throws -> URL {
        let directory = userDictionaryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        if !FileManager.default.fileExists(atPath: userDictionaryURL.path) {
            try SuggestionDictionary.userTemplate.write(to: userDictionaryURL, atomically: true, encoding: .utf8)
        }
        startDictionaryWatcher()
        return userDictionaryURL
    }

    /// 「ファイル > 提案辞書を開く…」: ファイルを用意して Finder で選択表示する (編集は好きなエディタで)
    func revealUserDictionary() {
        do {
            let url = try prepareUserDictionaryFile()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            errorMessage = String(localized: "提案辞書を作れません: \(error.localizedDescription)")
        }
    }
```

- [ ] **Step 4: メニューと受け口**

`FolderArt/FolderArtApp.swift` の `CommandGroup(after: .importExport)` に、「お気に入りのパックを読み込む…」の次の項目として追加:

```swift
                Button("提案辞書を開く…") {
                    NotificationCenter.default.post(name: AppModel.revealUserDictionaryNotification, object: nil)
                }
```

`FolderArt/ContentView.swift` の `.onReceive(… importPackNotification)` の次の行に追加:

```swift
        .onReceive(NotificationCenter.default.publisher(for: AppModel.revealUserDictionaryNotification)) { _ in model.revealUserDictionary() }
```

- [ ] **Step 5: 文言**

`scripts/localization/strings.json` に 3 行を追加:

```json
  "提案辞書を開く…": ["提案辞書を開く…", "Open Suggestion Dictionary…", "Vorschlagswörterbuch öffnen…", "Abrir diccionario de sugerencias…", "Ouvrir le dictionnaire de suggestions…", "제안 사전 열기…", "Abrir dicionário de sugestões…", "開啟建議字典…"],
  "提案辞書を読めません: %@": ["提案辞書を読めません: %@", "Cannot read the suggestion dictionary: %@", "Das Vorschlagswörterbuch kann nicht gelesen werden: %@", "No se puede leer el diccionario de sugerencias: %@", "Impossible de lire le dictionnaire de suggestions : %@", "제안 사전을 읽을 수 없습니다: %@", "Não é possível ler o dicionário de sugestões: %@", "無法讀取建議字典：%@"],
  "提案辞書を作れません: %@": ["提案辞書を作れません: %@", "Cannot create the suggestion dictionary: %@", "Das Vorschlagswörterbuch kann nicht angelegt werden: %@", "No se puede crear el diccionario de sugerencias: %@", "Impossible de créer le dictionnaire de suggestions : %@", "제안 사전을 만들 수 없습니다: %@", "Não é possível criar o dicionário de sugestões: %@", "無法建立建議字典：%@"]
```

```bash
python3 scripts/localization/build-xcstrings.py
python3 scripts/localization/build-xcstrings.py --check
```

Expected: `missing: 0`

- [ ] **Step 6: テストとビルド**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests -only-testing:FolderArtTests/LocalizationTests`)
Expected: 全 PASS (追加 6 件)

Run: テスト実行 (全体)
Expected: `Executed 278 tests, with 0 failures`、警告 0

Debug ビルド: `BUILD SUCCEEDED`。実機 (「提案辞書を開く…」で Finder が開く、エディタで保存すると提案が変わる、壊すとアラート 1 回) はコントローラーが行う。

- [ ] **Step 7: コミット**

```bash
git add FolderArt/AppModel.swift FolderArt/FolderArtApp.swift FolderArt/ContentView.swift scripts/localization/strings.json FolderArt/Resources/Localizable.xcstrings FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ ユーザー辞書を監視して自動で読み直し、「ファイル > 提案辞書を開く…」を追加"
```

---

### Task 7: 文言チェックの実物照合 (--stringsdata と check-compiled.sh)

**Files:**
- Modify: `scripts/localization/build-xcstrings.py`
- Create: `scripts/localization/check-compiled.sh`

**Interfaces:**
- Produces: `python3 scripts/localization/build-xcstrings.py --stringsdata <DerivedData>` (exit 0 = コードのキーが全部カタログにある、1 = 欠け、2 = `.stringsdata` が無い)、`scripts/localization/check-compiled.sh` (ビルドして上を実行)

- [ ] **Step 1: パーサとチェックを足す**

`scripts/localization/build-xcstrings.py` の `check()` の後に追加し、`__main__` を差し替える:

```python
def compiled_keys(root):
    """SWIFT_EMIT_LOC_STRINGS=YES のビルドが出す *.stringsdata から、コンパイラが抽出した Localizable のキーを集める。
    形式: {"source": "...swift", "tables": {"Localizable": [{"key": "...", "comment": "", "location": {...}}, ...]}, "version": 1}
    tables は「テーブル名 → 項目の配列」。文言の無いファイルは "tables": {}。項目はオブジェクトでも素の文字列でも受ける"""
    keys, files = set(), 0
    for path in glob.glob(os.path.join(root, "**", "*.stringsdata"), recursive=True):
        files += 1
        try:
            with open(path, encoding="utf-8") as f:
                doc = json.load(f)
        except (OSError, ValueError) as e:
            print(f"warning: cannot read {path}: {e}")
            continue
        tables = doc.get("tables") if isinstance(doc, dict) else None
        if not isinstance(tables, dict):
            continue
        for item in tables.get("Localizable") or []:
            key = item.get("key") if isinstance(item, dict) else item
            if isinstance(key, str):
                keys.add(key)
    return keys, files


def check_compiled(root):
    """コンパイラ抽出のキー (実物、%lld / %@ / %% を含む) と strings.json のキーを厳密に比較する"""
    keys, files = compiled_keys(root)
    if files == 0:
        print(f"no .stringsdata under {root} (build with SWIFT_EMIT_LOC_STRINGS=YES, see check-compiled.sh)")
        sys.exit(2)
    table = load("strings.json")
    missing = sorted(keys - set(table))
    unused = sorted(set(table) - keys)
    for k in missing:
        print(f"missing: {k!r}")
    for k in unused:
        print(f"unused (info): {k!r}")
    print(f"stringsdata files: {files}, compiled keys: {len(keys)}, missing: {len(missing)}, unused: {len(unused)}")
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    args = sys.argv[1:]
    if "--stringsdata" in args:
        i = args.index("--stringsdata")
        if i + 1 >= len(args):
            sys.exit("usage: build-xcstrings.py --stringsdata <DerivedData dir>")
        check_compiled(args[i + 1])
    elif "--check" in args:
        check()
    else:
        for name, dest in TARGETS:
            build(name, dest)
```

`import glob` を先頭の import に足す。ファイル冒頭の docstring に `--stringsdata` の 1 行を足す。

- [ ] **Step 2: 補助スクリプト**

`scripts/localization/check-compiled.sh`:

```bash
#!/bin/bash
# SWIFT_EMIT_LOC_STRINGS=YES で一時 DerivedData にビルドし、コンパイラが抽出した文言のキーと strings.json を厳密に突き合わせる。
# PR の前に 1 回走らせる (通常の --check は正規表現の簡易版)。
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d /tmp/folderart-loc.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$tmp" SWIFT_EMIT_LOC_STRINGS=YES 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -1
python3 scripts/localization/build-xcstrings.py --stringsdata "$tmp"
```

```bash
chmod +x scripts/localization/check-compiled.sh
```

- [ ] **Step 3: 動かす**

```bash
scripts/localization/check-compiled.sh
```

Expected: `BUILD SUCCEEDED` の後、最終行が `stringsdata files: N, compiled keys: K, missing: 0, unused: M`。`missing` があればそのキーを `strings.json` に足して再生成し、原因 (どのタスクの文言か) を報告する。`unused` には「日本語」「繁體中文」(訳さない `String`) と InfoPlist 用のキーは含まれず、`%lld` などコードから抽出されるキーは含まれないはず。おかしければ報告する。

`python3 scripts/localization/build-xcstrings.py --stringsdata /nonexistent` の exit code が 2 であることも確かめる。

- [ ] **Step 4: コミット**

```bash
git add scripts/localization/build-xcstrings.py scripts/localization/check-compiled.sh
git commit -m "chore: 🔧 文言チェックにコンパイラ抽出のキー (.stringsdata) との厳密照合を追加"
```

---

### Task 8: バージョン、README、最終確認 — コントローラー (親セッション) が実施

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: 1.5.0`, `CURRENT_PROJECT_VERSION: 8`)
- Modify: `README.md`

- [ ] **Step 1: バージョン**

`project.yml`: `MARKETING_VERSION: 1.5.0`、`CURRENT_PROJECT_VERSION: 8`。`xcodegen generate`。

- [ ] **Step 2: README**

機能一覧:
- 「お気に入りパック」の行の末尾に「一部だけの書き出しも可 — partial export from the … menu」を足す。
- 「フォルダ名と中身からの自動提案」の行の末尾に「自分の辞書 (`suggestions-user.json`) で語を足せる — add your own words with a user dictionary」を足す。

使い方 3 の末尾に 2 行:
```
   上下位置の既定は「下4%」(蓋つきのフォルダー本体の見た目の中心)
   The vertical position defaults to 4% down, the visual center of the folder body
```

使い方 6 の末尾に 2 行:
```
   「…」の「選んで書き出す…」で一部だけをパックにできる
   Use "Export Selected…" in the … menu to pack only some presets
```

「使い方」の後に節を新設:

```
## 提案辞書のカスタマイズ / Customizing suggestions

「ファイル > 提案辞書を開く…」で `suggestions-user.json` (Application Support/FolderArt) を Finder に表示します。無ければ例を 1 件入れて作ります。形式は同梱の辞書と同じで、保存すると自動で反映されます (壊れていれば知らせます)。同じ語が同梱辞書にもあれば自分の辞書が優先されます。記号名は記号タブの検索で探せます。
File > Open Suggestion Dictionary… reveals `suggestions-user.json` (Application Support/FolderArt) in the Finder, creating it with one example if needed. It uses the bundled dictionary's format and is reloaded automatically when saved (you are told if it is broken). Your entries win over bundled ones for the same word. Symbol names can be found in the Symbol tab's search.

```json
[
  {"keys": ["案件", "project"], "symbol": "folder.fill.badge.gearshape", "emoji": "🗂️"},
  {"keys": ["請求書"], "emoji": "🧾"}
]
```
```

「プロジェクト構成」に追加 (アルファベット順):
```
│   ├── PresetExportSelection.swift # 「選んで書き出す」の選択状態
│   ├── FileWatcher.swift       # ユーザー辞書の監視 (ディレクトリ + ファイル)
│   ├── PresetExportPickerView.swift # 「選んで書き出す」の popover
└── check-compiled.sh           # コンパイラ抽出のキーとの厳密照合
```
(それぞれ Models / Services / Views / scripts の該当位置に)

「注意」に 1 行: `欄の無い手書きのパックの上下位置は既定 (下4%) になります / A hand-written pack without a vertical position gets the default (4% down).`

- [ ] **Step 3: 全テスト、--check、実物照合**

```bash
python3 scripts/localization/build-xcstrings.py --check
scripts/localization/check-compiled.sh
```

Run: テスト実行 (全体)
Expected: `Executed 278 tests, with 0 failures`、警告 0、`missing: 0` (両方)

- [ ] **Step 4: コミット**

```bash
git add project.yml FolderArt.xcodeproj/project.pbxproj README.md
git commit -m "chore: 🔖 1.5.0 に更新し README (使い方・提案辞書のカスタマイズ・構成・注意) を更新"
```

- [ ] **Step 5: 仕上げ (コントローラー)**

実機確認 (起動直後のスライダーが「下4%」でプレビューが本体の中心、「選んで書き出す…」の popover: Esc / クリック外 / 0 件無効 / 2 件中 1 件を書き出して読み戻す、「提案辞書を開く…」で Finder、エディタで保存すると提案が変わる、壊すとアラート 1 回、直すと復帰、1.4.0 のお気に入りは見た目が変わらない) → Codex CLI の事前レビュー (`codex-companion.mjs review --wait --base develop --scope branch`、フォアグラウンド) → PR (日英併記) → Codex レビュー対応 (指摘が尽きるまで) → `develop` にマージ → `main` を同期 → v1.5.0 リリース → `~/アプリケーション/FolderArt.app` を入れ替え。
