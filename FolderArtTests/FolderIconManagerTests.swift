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
