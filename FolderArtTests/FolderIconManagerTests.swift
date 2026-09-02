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
}
