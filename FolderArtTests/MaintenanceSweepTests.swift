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
