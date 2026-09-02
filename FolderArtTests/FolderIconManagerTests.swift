import XCTest
import AppKit
@testable import FolderArt

final class FolderIconManagerTests: XCTestCase {

    private var testFolderURL: URL!
    private var backupRoot: URL!

    override func setUp() {
        super.setUp()
        testFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderIconTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testFolderURL, withIntermediateDirectories: true)
        // 本物の Application Support を汚さないよう、バックアップ先は毎回テンポラリに作る
        backupRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderIconBackups_\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFolderURL)
        try? FileManager.default.removeItem(at: backupRoot)
        super.tearDown()
    }

    private func makeManager() -> FolderIconManager {
        FolderIconManager(backupDirectory: backupRoot)
    }

    private func icon(_ color: NSColor) -> NSImage {
        TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: color)
    }

    func testBackupDirectoryIsCreated() {
        let manager = makeManager()
        XCTAssertTrue(FileManager.default.fileExists(atPath: manager.backupDirectory.path))
        XCTAssertEqual(manager.backupDirectory, backupRoot)
    }

    func testBackupReturnsNilWhenFolderHasNoCustomIcon() throws {
        XCTAssertNil(try makeManager().backupCurrentIcon(for: testFolderURL))
    }

    func testBackupReturnsPathWhenCustomIconExists() throws {
        let manager = makeManager()
        try manager.applyIcon(icon(.red), to: testFolderURL)          // Icon\r ができる
        let backupURL = try XCTUnwrap(try manager.backupCurrentIcon(for: testFolderURL))
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupURL.path))
        try manager.resetIcon(for: testFolderURL, backupURL: nil)
    }

    /// 2 回目の適用で FolderArt 自身の合成結果を「元のアイコン」として上書きしない
    func testSecondBackupKeepsTheOriginal() throws {
        let manager = makeManager()

        try manager.applyIcon(icon(.red), to: testFolderURL)
        let first = try XCTUnwrap(try manager.backupCurrentIcon(for: testFolderURL))
        let originalBytes = try Data(contentsOf: first)
        let originalDate = try FileManager.default.attributesOfItem(atPath: first.path)[.modificationDate] as? Date

        try manager.applyIcon(icon(.blue), to: testFolderURL)
        let second = try XCTUnwrap(try manager.backupCurrentIcon(for: testFolderURL))

        XCTAssertEqual(second, first)
        XCTAssertEqual(try Data(contentsOf: second), originalBytes)
        let secondDate = try FileManager.default.attributesOfItem(atPath: second.path)[.modificationDate] as? Date
        XCTAssertEqual(secondDate, originalDate)   // 書き直していない

        try manager.resetIcon(for: testFolderURL, backupURL: nil)
    }

    func testApplyAndResetIcon() throws {
        let manager = makeManager()
        try manager.applyIcon(icon(.red), to: testFolderURL)
        XCTAssertTrue(FileManager.default.fileExists(atPath: testFolderURL.appendingPathComponent("Icon\r").path))
        try manager.resetIcon(for: testFolderURL, backupURL: nil)
        XCTAssertFalse(FileManager.default.fileExists(atPath: testFolderURL.appendingPathComponent("Icon\r").path))
    }

    func testApplyToMissingFolderThrows() {
        let manager = makeManager()
        let missing = testFolderURL.appendingPathComponent("does-not-exist")
        XCTAssertThrowsError(try manager.applyIcon(icon(.red), to: missing))
    }

    func testResetOnMissingFolderThrows() throws {
        let manager = makeManager()
        try manager.applyIcon(icon(.red), to: testFolderURL)
        try FileManager.default.removeItem(at: testFolderURL)
        XCTAssertThrowsError(try manager.resetIcon(for: testFolderURL, backupURL: nil)) { error in
            guard case FolderIconError.folderNotFound = error else {
                return XCTFail("expected folderNotFound, got \(error)")
            }
        }
    }
}
