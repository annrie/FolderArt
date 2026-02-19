# FolderArt Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** macOS上でフォルダーアイコンにカスタム画像をオーバーレイ合成し、Finder上でアイコンを変更できるシングルウィンドウアプリを構築する。

**Architecture:** SwiftUI シングルウィンドウアプリ。Core Graphics で画像合成、NSWorkspace でアイコン管理。App Sandbox 準拠で Security-Scoped Bookmarks を使用。変更履歴は Application Support に JSON で保存。

**Tech Stack:** Swift 5.9+, SwiftUI, AppKit (NSWorkspace, NSImage), Core Graphics, XCTest, xcodegen, macOS 13+

---

## 前提条件チェック

```bash
# xcodegen のインストール確認
which xcodegen || brew install xcodegen

# Xcode Command Line Tools 確認
xcode-select -p

# 作業ディレクトリに移動
cd /Volumes/Logitec2/work/FolderArt
```

---

## Task 1: Xcode プロジェクトのセットアップ

**Files:**
- Create: `project.yml`
- Create: `FolderArt/FolderArt.entitlements`
- Create: `FolderArt/FolderArtApp.swift`
- Create: `FolderArtTests/FolderArtTests.swift` (placeholder)

### Step 1: project.yml を作成する

```bash
cat > /Volumes/Logitec2/work/FolderArt/project.yml << 'EOF'
name: FolderArt
options:
  bundleIdPrefix: com.example
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true
targets:
  FolderArt:
    type: application
    platform: macOS
    sources:
      - path: FolderArt
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.FolderArt
        MARKETING_VERSION: 1.0.0
        CURRENT_PROJECT_VERSION: 1
        SWIFT_VERSION: 5.9
        ENABLE_HARDENED_RUNTIME: YES
        INFOPLIST_FILE: FolderArt/Info.plist
    entitlements:
      path: FolderArt/FolderArt.entitlements
    info:
      path: FolderArt/Info.plist
      properties:
        LSMinimumSystemVersion: "$(MACOSX_DEPLOYMENT_TARGET)"
        CFBundleName: FolderArt
        NSHumanReadableCopyright: "Copyright © 2026. All rights reserved."
  FolderArtTests:
    type: bundle.unit-test
    platform: macOS
    sources:
      - path: FolderArtTests
    dependencies:
      - target: FolderArt
    settings:
      base:
        SWIFT_VERSION: 5.9
EOF
```

### Step 2: ディレクトリとエントリーポイントを作成する

```bash
mkdir -p /Volumes/Logitec2/work/FolderArt/FolderArt/Views
mkdir -p /Volumes/Logitec2/work/FolderArt/FolderArt/Services
mkdir -p /Volumes/Logitec2/work/FolderArt/FolderArt/Stores
mkdir -p /Volumes/Logitec2/work/FolderArt/FolderArt/Models
mkdir -p /Volumes/Logitec2/work/FolderArt/FolderArtTests
```

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
        .windowResizability(.contentSize)
        .defaultSize(width: 600, height: 700)
    }
}
```

`FolderArt/FolderArt.entitlements`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
	<key>com.apple.security.files.bookmarks.app-scope</key>
	<true/>
</dict>
</plist>
```

`FolderArtTests/FolderArtTests.swift`:
```swift
import XCTest

// テストはモジュールごとのファイルに分けて記述する
```

`FolderArt/ContentView.swift` (placeholder):
```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("FolderArt")
    }
}
```

### Step 3: xcodegen でプロジェクトを生成する

```bash
cd /Volumes/Logitec2/work/FolderArt && xcodegen generate
```

Expected: `FolderArt.xcodeproj` が生成される

### Step 4: ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add project.yml FolderArt/ FolderArtTests/ && \
git commit -m "chore: setup Xcode project with App Sandbox entitlements"
```

---

## Task 2: IconTask モデルと IconPosition 列挙型

**Files:**
- Create: `FolderArt/Models/IconTask.swift`
- Create: `FolderArtTests/IconTaskTests.swift`

### Step 1: テストを書く

`FolderArtTests/IconTaskTests.swift`:
```swift
import XCTest
@testable import FolderArt

final class IconTaskTests: XCTestCase {

    func testIconTaskIsEncodableAndDecodable() throws {
        let task = IconTask(
            folderPath: "/Users/test/Documents",
            bookmarkData: Data(),
            appliedAt: Date(timeIntervalSince1970: 1000),
            backupPath: "/backups/test/original.png",
            imageName: "photo.png",
            position: .center,
            scale: 0.6,
            opacity: 0.9
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(IconTask.self, from: data)

        XCTAssertEqual(decoded.folderPath, task.folderPath)
        XCTAssertEqual(decoded.imageName, task.imageName)
        XCTAssertEqual(decoded.position, .center)
        XCTAssertEqual(decoded.scale, 0.6)
        XCTAssertEqual(decoded.opacity, 0.9)
    }

    func testIconPositionHasTwoCases() {
        let center = IconPosition.center
        let badge = IconPosition.badge
        XCTAssertNotEqual(center, badge)
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/IconTaskTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

Expected: `BUILD FAILED` (IconTask が未定義)

### Step 3: モデルを実装する

`FolderArt/Models/IconTask.swift`:
```swift
import Foundation

enum IconPosition: String, Codable, CaseIterable, Equatable {
    case center = "center"
    case badge  = "badge"

    var displayName: String {
        switch self {
        case .center: return "中央オーバーレイ"
        case .badge:  return "右下バッジ"
        }
    }
}

struct IconTask: Codable, Identifiable, Equatable {
    let id: UUID
    let folderPath: String
    let bookmarkData: Data
    let appliedAt: Date
    let backupPath: String
    let imageName: String
    let position: IconPosition
    let scale: Double
    let opacity: Double

    init(
        id: UUID = UUID(),
        folderPath: String,
        bookmarkData: Data,
        appliedAt: Date = Date(),
        backupPath: String,
        imageName: String,
        position: IconPosition,
        scale: Double,
        opacity: Double
    ) {
        self.id = id
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.appliedAt = appliedAt
        self.backupPath = backupPath
        self.imageName = imageName
        self.position = position
        self.scale = scale
        self.opacity = opacity
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/IconTaskTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

Expected: `Test Suite 'IconTaskTests' passed`

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Models/IconTask.swift FolderArtTests/IconTaskTests.swift && \
git commit -m "feat: add IconTask model and IconPosition enum with Codable support"
```

---

## Task 3: BookmarkManager — Security-Scoped Bookmarks

**Files:**
- Create: `FolderArt/Services/BookmarkManager.swift`
- Create: `FolderArtTests/BookmarkManagerTests.swift`

### Step 1: テストを書く

`FolderArtTests/BookmarkManagerTests.swift`:
```swift
import XCTest
@testable import FolderArt

final class BookmarkManagerTests: XCTestCase {

    func testCreateAndResolveBookmark() throws {
        // テスト用の一時ディレクトリを使用
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderArtTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = try BookmarkManager.createBookmark(for: tempDir)
        XCTAssertFalse(data.isEmpty)

        let resolved = try BookmarkManager.resolveBookmark(data)
        XCTAssertEqual(resolved.path, tempDir.path)
    }

    func testResolveInvalidBookmarkThrows() {
        let invalidData = Data("invalid".utf8)
        XCTAssertThrowsError(try BookmarkManager.resolveBookmark(invalidData))
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/BookmarkManagerTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

### Step 3: BookmarkManager を実装する

`FolderArt/Services/BookmarkManager.swift`:
```swift
import Foundation

enum BookmarkError: LocalizedError {
    case creationFailed(String)
    case resolutionFailed(String)
    case stale

    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "ブックマーク作成失敗: \(msg)"
        case .resolutionFailed(let msg): return "ブックマーク解決失敗: \(msg)"
        case .stale: return "ブックマークが古くなっています"
        }
    }
}

class BookmarkManager {

    /// Security-Scoped Bookmark を作成する
    static func createBookmark(for url: URL) throws -> Data {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            // App Sandbox 外 (テスト環境など) ではセキュリティスコープなしで試みる
            do {
                let data = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return data
            } catch {
                throw BookmarkError.creationFailed(error.localizedDescription)
            }
        }
    }

    /// Security-Scoped Bookmark を解決して URL を返す
    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { throw BookmarkError.stale }
            return url
        } catch let error as BookmarkError {
            throw error
        } catch {
            // セキュリティスコープなしで再試行（テスト環境対応）
            var isStale2 = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale2
                )
                return url
            } catch {
                throw BookmarkError.resolutionFailed(error.localizedDescription)
            }
        }
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/BookmarkManagerTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Services/BookmarkManager.swift FolderArtTests/BookmarkManagerTests.swift && \
git commit -m "feat: add BookmarkManager for Security-Scoped Bookmarks"
```

---

## Task 4: IconComposer — Core Graphics 画像合成

**Files:**
- Create: `FolderArt/Services/IconComposer.swift`
- Create: `FolderArtTests/IconComposerTests.swift`

### Step 1: テストを書く

`FolderArtTests/IconComposerTests.swift`:
```swift
import XCTest
import AppKit
@testable import FolderArt

final class IconComposerTests: XCTestCase {

    private func makeTestImage(size: CGSize, color: NSColor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        color.setFill()
        NSRect(origin: .zero, size: size).fill()
        image.unlockFocus()
        return image
    }

    func testCenterCalculationIsMiddle() {
        let settings = CompositionSettings(position: .center, scale: 0.5, opacity: 1.0)
        let imageSize = CGSize(width: 100, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        let expectedSide = containerSize.width * settings.scale  // 256
        XCTAssertEqual(rect.width, expectedSide, accuracy: 0.1)
        XCTAssertEqual(rect.height, expectedSide, accuracy: 0.1)
        // 中央配置のX座標: (512 - 256) / 2 = 128
        XCTAssertEqual(rect.origin.x, (containerSize.width - expectedSide) / 2, accuracy: 0.1)
        XCTAssertEqual(rect.origin.y, (containerSize.height - expectedSide) / 2, accuracy: 0.1)
    }

    func testBadgeCalculationIsBottomRight() {
        let settings = CompositionSettings(position: .badge, scale: 0.6, opacity: 1.0)
        let imageSize = CGSize(width: 100, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        // バッジは右下 → x + width が containerSize.width 付近
        XCTAssertGreaterThan(rect.origin.x, containerSize.width / 2)
        // y は下部（NSRect は bottom-left origin）
        XCTAssertLessThan(rect.origin.y, containerSize.height / 2)
    }

    func testAspectRatioPreserved() {
        let settings = CompositionSettings(position: .center, scale: 0.8, opacity: 1.0)
        // 2:1 の横長画像
        let imageSize = CGSize(width: 200, height: 100)
        let containerSize = CGSize(width: 512, height: 512)

        let rect = IconComposer.calculateRect(
            for: imageSize,
            in: containerSize,
            settings: settings
        )

        let aspectRatio = rect.width / rect.height
        XCTAssertEqual(aspectRatio, 2.0, accuracy: 0.01)
    }

    func testComposeReturnsNonNilImage() throws {
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderArtIconTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let customImage = makeTestImage(size: CGSize(width: 100, height: 100), color: .red)
        let settings = CompositionSettings(position: .center, scale: 0.6, opacity: 0.9)

        let result = IconComposer.compose(
            folderPath: tempDir.path,
            customImage: customImage,
            settings: settings
        )

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.size, IconComposer.iconSize)
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/IconComposerTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

### Step 3: IconComposer を実装する

`FolderArt/Services/IconComposer.swift`:
```swift
import AppKit
import CoreGraphics

struct CompositionSettings: Equatable {
    var position: IconPosition = .center
    var scale: Double = 0.6      // 0.2 ... 1.0
    var opacity: Double = 0.9    // 0.1 ... 1.0
}

class IconComposer {
    static let iconSize = CGSize(width: 512, height: 512)

    /// フォルダーアイコンにカスタム画像を合成して返す
    static func compose(
        folderPath: String,
        customImage: NSImage,
        settings: CompositionSettings
    ) -> NSImage? {
        let size = iconSize

        guard let bitmapRep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: Int(size.width),
            pixelsHigh: Int(size.height),
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return nil }

        NSGraphicsContext.saveGraphicsState()
        defer { NSGraphicsContext.restoreGraphicsState() }

        guard let ctx = NSGraphicsContext(bitmapImageRep: bitmapRep) else { return nil }
        NSGraphicsContext.current = ctx

        // ベースのフォルダーアイコンを描画
        let folderIcon = NSWorkspace.shared.icon(forFile: folderPath)
        folderIcon.draw(in: NSRect(origin: .zero, size: size))

        // カスタム画像の描画範囲を計算
        let customRect = calculateRect(
            for: customImage.size,
            in: size,
            settings: settings
        )

        // カスタム画像を不透明度付きで描画
        customImage.draw(
            in: customRect,
            from: NSRect(origin: .zero, size: customImage.size),
            operation: .sourceOver,
            fraction: settings.opacity
        )

        let result = NSImage(size: size)
        result.addRepresentation(bitmapRep)
        return result
    }

    /// 配置設定に基づいてカスタム画像の描画 Rect を計算する
    static func calculateRect(
        for imageSize: CGSize,
        in containerSize: CGSize,
        settings: CompositionSettings
    ) -> NSRect {
        let aspectRatio = imageSize.width > 0 ? imageSize.width / imageSize.height : 1.0
        let customWidth: CGFloat
        let customHeight: CGFloat

        switch settings.position {
        case .center:
            let maxDimension = min(containerSize.width, containerSize.height) * settings.scale
            if aspectRatio >= 1 {
                customWidth  = maxDimension
                customHeight = maxDimension / aspectRatio
            } else {
                customHeight = maxDimension
                customWidth  = maxDimension * aspectRatio
            }
            let x = (containerSize.width  - customWidth)  / 2
            let y = (containerSize.height - customHeight) / 2
            return NSRect(x: x, y: y, width: customWidth, height: customHeight)

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
            let y = padding
            return NSRect(x: x, y: y, width: customWidth, height: customHeight)
        }
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/IconComposerTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

Expected: `Test Suite 'IconComposerTests' passed`

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Services/IconComposer.swift FolderArtTests/IconComposerTests.swift && \
git commit -m "feat: add IconComposer with Core Graphics compositing"
```

---

## Task 5: FolderIconManager — NSWorkspace アイコン操作

**Files:**
- Create: `FolderArt/Services/FolderIconManager.swift`
- Create: `FolderArtTests/FolderIconManagerTests.swift`

### Step 1: テストを書く

`FolderArtTests/FolderIconManagerTests.swift`:
```swift
import XCTest
import AppKit
@testable import FolderArt

final class FolderIconManagerTests: XCTestCase {

    private var testFolderURL: URL!

    override func setUp() {
        super.setUp()
        testFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderIconTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testFolderURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFolderURL)
        super.tearDown()
    }

    func testBackupDirectoryIsCreated() {
        let manager = FolderIconManager()
        let backupURL = manager.backupDirectory
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
    }

    func testBackupReturnsPath() throws {
        let manager = FolderIconManager()
        let backupURL = try manager.backupCurrentIcon(for: testFolderURL)
        XCTAssertNotNil(backupURL)
        if let url = backupURL {
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path))
        }
    }

    func testApplyAndResetIcon() throws {
        let manager = FolderIconManager()

        // カスタムアイコン作成
        let customImage = NSImage(size: CGSize(width: 64, height: 64))
        customImage.lockFocus()
        NSColor.red.setFill()
        NSRect(origin: .zero, size: customImage.size).fill()
        customImage.unlockFocus()

        // バックアップ
        let backupURL = try manager.backupCurrentIcon(for: testFolderURL)

        // 適用
        let success = manager.applyIcon(customImage, to: testFolderURL)
        XCTAssertTrue(success)

        // リセット
        manager.resetIcon(for: testFolderURL, backupURL: backupURL)
        // エラーがなければOK（目視確認はUIテストで行う）
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/FolderIconManagerTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

### Step 3: FolderIconManager を実装する

`FolderArt/Services/FolderIconManager.swift`:
```swift
import AppKit
import Foundation

class FolderIconManager {

    let backupDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("FolderArt/backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 現在のフォルダーアイコンをバックアップして保存先 URL を返す
    func backupCurrentIcon(for folderURL: URL) throws -> URL? {
        let folderID = folderURL.path
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            ?? UUID().uuidString

        let backupDir = backupDirectory.appendingPathComponent(folderID)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let currentIcon = NSWorkspace.shared.icon(forFile: folderURL.path)
        let backupURL = backupDir.appendingPathComponent("original.png")

        guard let tiff   = currentIcon.tiffRepresentation,
              let bitmap  = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        try pngData.write(to: backupURL)
        return backupURL
    }

    /// 合成済みアイコンをフォルダーに適用する
    @discardableResult
    func applyIcon(_ icon: NSImage, to folderURL: URL) -> Bool {
        return NSWorkspace.shared.setIcon(icon, forFile: folderURL.path, options: [])
    }

    /// フォルダーのアイコンをバックアップ（または デフォルト）に戻す
    func resetIcon(for folderURL: URL, backupURL: URL?) {
        if let backupURL = backupURL,
           let backupImage = NSImage(contentsOf: backupURL) {
            NSWorkspace.shared.setIcon(backupImage, forFile: folderURL.path, options: [])
        } else {
            NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: [])
        }
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/FolderIconManagerTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Services/FolderIconManager.swift FolderArtTests/FolderIconManagerTests.swift && \
git commit -m "feat: add FolderIconManager for NSWorkspace icon operations"
```

---

## Task 6: HistoryStore — 変更履歴の永続化

**Files:**
- Create: `FolderArt/Stores/HistoryStore.swift`
- Create: `FolderArtTests/HistoryStoreTests.swift`

### Step 1: テストを書く

`FolderArtTests/HistoryStoreTests.swift`:
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

    private func makeTask(folderPath: String = "/test/folder") -> IconTask {
        IconTask(
            folderPath: folderPath,
            bookmarkData: Data(),
            backupPath: "/backup/original.png",
            imageName: "test.png",
            position: .center,
            scale: 0.6,
            opacity: 0.9
        )
    }

    func testAddTaskIncreasesCount() {
        XCTAssertEqual(store.tasks.count, 0)
        store.add(makeTask())
        XCTAssertEqual(store.tasks.count, 1)
    }

    func testNewestTaskIsFirst() {
        store.add(makeTask(folderPath: "/folder/A"))
        store.add(makeTask(folderPath: "/folder/B"))
        XCTAssertEqual(store.tasks.first?.folderPath, "/folder/B")
    }

    func testRemoveTaskDecreasesCount() {
        let task = makeTask()
        store.add(task)
        store.remove(task)
        XCTAssertEqual(store.tasks.count, 0)
    }

    func testPersistenceAcrossInstances() {
        let task = makeTask()
        store.add(task)

        let store2 = HistoryStore(storageURL: tempHistoryURL)
        XCTAssertEqual(store2.tasks.count, 1)
        XCTAssertEqual(store2.tasks.first?.folderPath, task.folderPath)
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/HistoryStoreTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

### Step 3: HistoryStore を実装する

`FolderArt/Stores/HistoryStore.swift`:
```swift
import Foundation
import Combine

class HistoryStore: ObservableObject {
    @Published private(set) var tasks: [IconTask] = []

    private let storageURL: URL

    /// 本番用イニシャライザー（Application Support を使用）
    convenience init() {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("FolderArt")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        self.init(storageURL: dir.appendingPathComponent("history.json"))
    }

    /// テスト用イニシャライザー（任意の URL を指定可能）
    init(storageURL: URL) {
        self.storageURL = storageURL
        load()
    }

    func add(_ task: IconTask) {
        tasks.insert(task, at: 0)
        save()
    }

    func remove(_ task: IconTask) {
        tasks.removeAll { $0.id == task.id }
        save()
    }

    private func load() {
        guard let data = try? Data(contentsOf: storageURL),
              let loaded = try? JSONDecoder().decode([IconTask].self, from: data) else {
            return
        }
        tasks = loaded
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(tasks) else { return }
        try? data.write(to: storageURL)
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/HistoryStoreTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

Expected: `Test Suite 'HistoryStoreTests' passed`

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Stores/HistoryStore.swift FolderArtTests/HistoryStoreTests.swift && \
git commit -m "feat: add HistoryStore with JSON persistence"
```

---

## Task 7: ContentViewModel — メインビジネスロジック

**Files:**
- Create: `FolderArt/ContentViewModel.swift`
- Create: `FolderArtTests/ContentViewModelTests.swift`

### Step 1: テストを書く

`FolderArtTests/ContentViewModelTests.swift`:
```swift
import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class ContentViewModelTests: XCTestCase {

    private var testFolderURL: URL!

    override func setUp() {
        super.setUp()
        testFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testFolderURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFolderURL)
        super.tearDown()
    }

    func testInitialStateIsEmpty() {
        let vm = ContentViewModel()
        XCTAssertNil(vm.selectedFolderURL)
        XCTAssertNil(vm.selectedImage)
        XCTAssertNil(vm.previewImage)
        XCTAssertFalse(vm.canApply)
    }

    func testCanApplyBecomeTrueWhenBothSelected() {
        let vm = ContentViewModel()
        vm.selectedFolderURL = testFolderURL
        vm.selectedImage = NSImage(size: CGSize(width: 10, height: 10))
        XCTAssertTrue(vm.canApply)
    }

    func testUpdatePreviewGeneratesImage() {
        let vm = ContentViewModel()
        vm.selectedFolderURL = testFolderURL

        let image = NSImage(size: CGSize(width: 100, height: 100))
        image.lockFocus(); NSColor.blue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        vm.selectedImage = image
        vm.updatePreview()

        XCTAssertNotNil(vm.previewImage)
    }
}
```

### Step 2: テストが失敗することを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/ContentViewModelTests 2>&1 | grep -E "(FAIL|error:|BUILD)"
```

### Step 3: ContentViewModel を実装する

`FolderArt/ContentViewModel.swift`:
```swift
import AppKit
import SwiftUI
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - 入力
    @Published var selectedFolderURL: URL?   { didSet { updatePreview() } }
    @Published var selectedImage: NSImage?   { didSet { updatePreview() } }
    @Published var imageName: String = ""

    // MARK: - 設定
    @Published var settings = CompositionSettings() { didSet { updatePreview() } }

    // MARK: - 出力
    @Published var previewImage: NSImage?
    @Published var errorMessage: String?
    @Published var isApplying: Bool = false

    // MARK: - 依存サービス
    let historyStore: HistoryStore
    private let iconManager = FolderIconManager()

    init(historyStore: HistoryStore = HistoryStore()) {
        self.historyStore = historyStore
    }

    var canApply: Bool {
        selectedFolderURL != nil && selectedImage != nil
    }

    // MARK: - プレビュー更新

    func updatePreview() {
        guard let folderURL = selectedFolderURL,
              let image = selectedImage else {
            previewImage = nil
            return
        }
        previewImage = IconComposer.compose(
            folderPath: folderURL.path,
            customImage: image,
            settings: settings
        )
    }

    // MARK: - アイコン適用

    func applyIcon() async {
        guard let folderURL = selectedFolderURL,
              let image = selectedImage,
              let composedImage = previewImage else { return }

        isApplying = true
        defer { isApplying = false }

        do {
            // バックアップ
            let backupURL = try iconManager.backupCurrentIcon(for: folderURL)

            // Security-Scoped Bookmark 作成
            let bookmarkData = try BookmarkManager.createBookmark(for: folderURL)

            // アイコン適用
            let success = iconManager.applyIcon(composedImage, to: folderURL)
            guard success else {
                errorMessage = "アイコンの適用に失敗しました。フォルダーへの書き込み権限を確認してください。"
                return
            }

            // 履歴に追加
            let task = IconTask(
                folderPath: folderURL.path,
                bookmarkData: bookmarkData,
                backupPath: backupURL?.path ?? "",
                imageName: imageName.isEmpty ? "カスタム画像" : imageName,
                position: settings.position,
                scale: settings.scale,
                opacity: settings.opacity
            )
            historyStore.add(task)
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - アイコンリセット

    func resetIcon(task: IconTask) {
        guard let resolvedURL = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            errorMessage = "フォルダーへのアクセスが無効になっています。"
            return
        }

        let backupURL = task.backupPath.isEmpty ? nil : URL(fileURLWithPath: task.backupPath)
        _ = resolvedURL.startAccessingSecurityScopedResource()
        defer { resolvedURL.stopAccessingSecurityScopedResource() }

        iconManager.resetIcon(for: resolvedURL, backupURL: backupURL)
        historyStore.remove(task)
    }

    // MARK: - フォルダー選択

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "フォルダーを選択"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
        }
    }

    // MARK: - 画像選択

    func selectImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP]
        panel.prompt = "画像を選択"

        if panel.runModal() == .OK, let url = panel.url,
           let image = NSImage(contentsOf: url) {
            selectedImage = image
            imageName = url.lastPathComponent
        }
    }
}
```

### Step 4: テストが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' \
  -only-testing:FolderArtTests/ContentViewModelTests 2>&1 | grep -E "(PASS|FAIL|TEST)"
```

### Step 5: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/ContentViewModel.swift FolderArtTests/ContentViewModelTests.swift && \
git commit -m "feat: add ContentViewModel with apply/reset/preview logic"
```

---

## Task 8: DropZoneView — ドロップゾーンコンポーネント

**Files:**
- Create: `FolderArt/Views/DropZoneView.swift`

### Step 1: DropZoneView を実装する（ユニットテストは不要。Xcode Preview で確認）

`FolderArt/Views/DropZoneView.swift`:
```swift
import SwiftUI
import UniformTypeIdentifiers

struct DropZoneView: View {
    enum Mode {
        case folder
        case image
    }

    let mode: Mode
    let onDropURL: (URL) -> Void
    let onTapButton: () -> Void

    @State private var isTargeted = false
    private let displayURL: URL?

    init(
        mode: Mode,
        selectedURL: URL?,
        onDropURL: @escaping (URL) -> Void,
        onTapButton: @escaping () -> Void
    ) {
        self.mode = mode
        self.displayURL = selectedURL
        self.onDropURL = onDropURL
        self.onTapButton = onTapButton
    }

    private var acceptedTypes: [UTType] {
        switch mode {
        case .folder: return [.folder]
        case .image:  return [.png, .jpeg, .heic, .gif, .webP, .image]
        }
    }

    private var icon: String {
        switch mode {
        case .folder: return "folder.fill"
        case .image:  return "photo.fill"
        }
    }

    private var label: String {
        switch mode {
        case .folder: return "フォルダーをここにドロップ"
        case .image:  return "画像をここにドロップ"
        }
    }

    private var buttonLabel: String {
        switch mode {
        case .folder: return "フォルダーを選択..."
        case .image:  return "画像を選択..."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

            Button(buttonLabel, action: onTapButton)
                .buttonStyle(.borderless)

            if let url = displayURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            let typeID: String
            switch mode {
            case .folder: typeID = UTType.folder.identifier
            case .image:  typeID = UTType.fileURL.identifier
            }
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { onDropURL(url) }
            }
            return true
        }
        .padding(4)
    }
}
```

### Step 2: ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

### Step 3: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Views/DropZoneView.swift && \
git commit -m "feat: add DropZoneView with drag-and-drop support"
```

---

## Task 9: ControlsView — スライダー・位置設定

**Files:**
- Create: `FolderArt/Views/ControlsView.swift`

### Step 1: ControlsView を実装する

`FolderArt/Views/ControlsView.swift`:
```swift
import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 位置選択
            HStack {
                Text("画像の配置:")
                    .font(.callout)
                    .frame(width: 90, alignment: .trailing)

                Picker("", selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            // サイズスライダー
            SliderRow(
                label: "サイズ:",
                value: $settings.scale,
                range: 0.2...1.0,
                format: { "\(Int($0 * 100))%" }
            )

            // 不透明度スライダー
            SliderRow(
                label: "不透明度:",
                value: $settings.opacity,
                range: 0.1...1.0,
                format: { "\(Int($0 * 100))%" }
            )
        }
        .padding(.horizontal)
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 90, alignment: .trailing)
            Slider(value: $value, in: range)
            Text(format(value))
                .font(.callout)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
```

### Step 2: ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

### Step 3: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Views/ControlsView.swift && \
git commit -m "feat: add ControlsView with position/scale/opacity controls"
```

---

## Task 10: HistoryView — 変更履歴シート

**Files:**
- Create: `FolderArt/Views/HistoryView.swift`

### Step 1: HistoryView を実装する

`FolderArt/Views/HistoryView.swift`:
```swift
import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    let onReset: (IconTask) -> Void

    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("変更履歴")
                    .font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if historyStore.tasks.isEmpty {
                Spacer()
                Text("変更履歴はありません")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(historyStore.tasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: task.folderPath).lastPathComponent)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(task.imageName) · \(task.position.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(dateFormatter.string(from: task.appliedAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("リセット") {
                                onReset(task)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 400, height: 360)
    }
}
```

### Step 2: ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

### Step 3: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/Views/HistoryView.swift && \
git commit -m "feat: add HistoryView sheet with reset per entry"
```

---

## Task 11: ContentView — メインUIの組み立て

**Files:**
- Modify: `FolderArt/ContentView.swift`

### Step 1: ContentView を完成させる

`FolderArt/ContentView.swift`:
```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var vm = ContentViewModel()
    @State private var showHistory = false
    @State private var showError   = false

    var body: some View {
        VStack(spacing: 0) {

            // ツールバー
            HStack {
                Text("FolderArt")
                    .font(.headline)
                Spacer()
                Button {
                    showHistory = true
                } label: {
                    Label("履歴", systemImage: "clock")
                }
                .buttonStyle(.borderless)
            }
            .padding(.horizontal)
            .padding(.vertical, 10)

            Divider()

            // ドロップゾーン（上半分）
            HStack(spacing: 16) {
                DropZoneView(
                    mode: .folder,
                    selectedURL: vm.selectedFolderURL,
                    onDropURL: { url in vm.selectedFolderURL = url },
                    onTapButton: { vm.selectFolder() }
                )

                DropZoneView(
                    mode: .image,
                    selectedURL: vm.selectedImage != nil
                        ? URL(fileURLWithPath: vm.imageName)
                        : nil,
                    onDropURL: { url in
                        if let img = NSImage(contentsOf: url) {
                            vm.selectedImage = img
                            vm.imageName = url.lastPathComponent
                        }
                    },
                    onTapButton: { vm.selectImage() }
                )
            }
            .padding()

            Divider()

            // 設定コントロール
            ControlsView(settings: $vm.settings)
                .padding(.vertical, 8)

            Divider()

            // プレビューエリア
            VStack(spacing: 8) {
                Text("プレビュー")
                    .font(.caption)
                    .foregroundColor(.secondary)

                if let preview = vm.previewImage {
                    Image(nsImage: preview)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 128, height: 128)
                        .shadow(radius: 4)
                } else {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(Color.secondary.opacity(0.1))
                        .frame(width: 128, height: 128)
                        .overlay(
                            Text("フォルダーと\n画像を選択")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .multilineTextAlignment(.center)
                        )
                }
            }
            .padding()

            Divider()

            // アクションボタン
            HStack {
                Button {
                    if let task = vm.historyStore.tasks.first(where: {
                        $0.folderPath == vm.selectedFolderURL?.path
                    }) {
                        vm.resetIcon(task: task)
                    }
                } label: {
                    Label("リセット", systemImage: "arrow.uturn.backward")
                }
                .disabled(vm.selectedFolderURL == nil)

                Spacer()

                Button {
                    Task { await vm.applyIcon() }
                } label: {
                    Label(
                        vm.isApplying ? "適用中..." : "アイコンを適用",
                        systemImage: "checkmark.circle.fill"
                    )
                }
                .buttonStyle(.borderedProminent)
                .disabled(!vm.canApply || vm.isApplying)
            }
            .padding()
        }
        .sheet(isPresented: $showHistory) {
            HistoryView(
                historyStore: vm.historyStore,
                onReset: { task in
                    vm.resetIcon(task: task)
                    showHistory = false
                }
            )
        }
        .onChange(of: vm.errorMessage) { msg in
            if msg != nil { showError = true }
        }
        .alert("エラー", isPresented: $showError) {
            Button("OK") { vm.errorMessage = nil }
        } message: {
            Text(vm.errorMessage ?? "")
        }
    }
}
```

### Step 2: ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -5
```

Expected: `** BUILD SUCCEEDED **`

### Step 3: 全テストを実行する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | \
  grep -E "(Test Suite|PASS|FAIL|error:)"
```

Expected: すべてのテストスイートが `passed`

### Step 4: コミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add FolderArt/ContentView.swift && \
git commit -m "feat: complete ContentView with all UI components assembled"
```

---

## Task 12: 最終確認・アーカイブビルド

### Step 1: 全テストが通ることを最終確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild test -scheme FolderArt -destination 'platform=macOS,arch=arm64' 2>&1 | tail -10
```

Expected: `** TEST SUCCEEDED **`

### Step 2: Release ビルドが通ることを確認する

```bash
cd /Volumes/Logitec2/work/FolderArt && \
xcodebuild build -scheme FolderArt -configuration Release \
  -destination 'platform=macOS,arch=arm64' 2>&1 | tail -3
```

### Step 3: タグを打ってコミット

```bash
cd /Volumes/Logitec2/work/FolderArt && \
git add -A && \
git commit -m "feat: complete FolderArt v1.0.0 initial implementation" && \
git tag v1.0.0
```

---

## テスト一覧まとめ

| テストクラス | 対象 | テスト数 |
|---|---|---|
| `IconTaskTests` | データモデルの Codable | 2 |
| `BookmarkManagerTests` | Bookmark 作成・解決 | 2 |
| `IconComposerTests` | 画像合成・配置計算 | 4 |
| `FolderIconManagerTests` | NSWorkspace アイコン操作 | 3 |
| `HistoryStoreTests` | 履歴の追加・削除・永続化 | 4 |
| `ContentViewModelTests` | ViewModel の状態管理 | 3 |

**合計: 18 テスト**

---

## 注意事項

- `NSWorkspace.setIcon` は App Sandbox 内でも、ユーザーが明示的に選択したフォルダーであれば動作する
- App Store 審査では `NSOpenPanel` による明示的なユーザー同意が必要（D&D のみでの権限取得も可）
- Security-Scoped Bookmark の `withSecurityScope` オプションはサンドボックス環境でのみ動作するため、テスト時はフォールバックが必要（実装済み）
- DropZoneView の `onDrop` の UTType 識別子は macOS バージョンにより挙動が異なる場合があるため、実機での動作確認を推奨
