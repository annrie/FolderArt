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

    /// このセッション (起動時刻 now) 以降に作られたバックアップは、まだ履歴の保存が終わっていないだけかもしれない。
    /// 参照されていなくても消してはいけない (Finding 1: 作成とスイープの競合)
    func testKeepsUnreferencedBackupCreatedDuringThisSession() throws {
        let orphan = try makeBackup("orphan")
        let r = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                     backupDirectory: backups, appSupportDirectory: root,
                                     now: Date().addingTimeInterval(-60))
        XCTAssertEqual(r.backupsRemoved, 0)
        XCTAssertTrue(FileManager.default.fileExists(atPath: orphan))
    }

    /// 起動時刻より前に作られた孤児バックアップは、前回までのセッションのものなので消してよい
    func testRemovesUnreferencedBackupCreatedBeforeLaunch() throws {
        let orphan = try makeBackup("orphan")
        let r = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                     backupDirectory: backups, appSupportDirectory: root,
                                     now: Date().addingTimeInterval(60))
        XCTAssertEqual(r.backupsRemoved, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: orphan))
    }

    /// backupDirectory 直下は本来サブディレクトリしか無いはずだが、.DS_Store のような迷子ファイルは
    /// 対象外 (Finding 3: ディレクトリだけを掃除する)
    func testStrayFileUnderBackupDirectorySurvives() throws {
        let strayFile = backups.appendingPathComponent(".DS_Store")
        try Data([0]).write(to: strayFile)
        _ = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                 backupDirectory: backups, appSupportDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: strayFile.path))
    }

    /// 子を全部消しても backups ディレクトリ自体は残る (Finding 4a)
    func testBackupRootDirectoryStillExistsAfterSweepingAllChildren() throws {
        _ = try makeBackup("orphan")
        _ = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                 backupDirectory: backups, appSupportDirectory: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backups.path))
    }

    /// backupDirectory/appSupportDirectory が存在しなくても例外にならず 0 件で返る (Finding 4b)
    func testRunOnMissingDirectoriesReturnsZeroResult() {
        let missingBackups = root.appendingPathComponent("does-not-exist-backups")
        let missingAppSupport = root.appendingPathComponent("does-not-exist-appsupport")
        let r = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                     backupDirectory: missingBackups, appSupportDirectory: missingAppSupport)
        XCTAssertEqual(r, MaintenanceSweep.Result(backupsRemoved: 0, corruptFilesRemoved: 0))
    }

    // MARK: - 列挙と削除の分離 (適用が再利用したバックアップを消さない)

    func testCandidatesExcludeReferencedNewAndNonDirectories() throws {
        let kept = try makeBackup("kept")
        _ = try makeBackup("orphan")
        try Data([0]).write(to: backups.appendingPathComponent(".DS_Store"))
        // now が過去 = 全部「起動後」に作られた扱い → 候補なし
        let past = Date().addingTimeInterval(-60)
        XCTAssertEqual(MaintenanceSweep.backupCandidates(referencedBackupPaths: [kept], historyLoaded: true,
                                                         backupDirectory: backups, now: past), [])
        let future = Date().addingTimeInterval(60)
        let candidates = MaintenanceSweep.backupCandidates(referencedBackupPaths: [kept], historyLoaded: true,
                                                           backupDirectory: backups, now: future)
        XCTAssertEqual(candidates.map(\.lastPathComponent), ["orphan"])
        XCTAssertEqual(MaintenanceSweep.backupCandidates(referencedBackupPaths: [kept], historyLoaded: false,
                                                         backupDirectory: backups, now: future), [])
    }

    func testRemoveSkipsCandidatesReferencedSinceTheScan() throws {
        let a = try makeBackup("a"), b = try makeBackup("b")
        let future = Date().addingTimeInterval(60)
        let candidates = MaintenanceSweep.backupCandidates(referencedBackupPaths: [], historyLoaded: true,
                                                           backupDirectory: backups, now: future)
        XCTAssertEqual(Set(candidates.map(\.lastPathComponent)), ["a", "b"])
        // 列挙後に適用が a を再利用して履歴に載せた → a は消さない
        let removed = MaintenanceSweep.removeBackupDirectories(candidates, stillReferencedBackupPaths: [a])
        XCTAssertEqual(removed, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a))
        XCTAssertFalse(FileManager.default.fileExists(atPath: b))
    }

    func testOnlyQuarantineFileNamesAreSwept() throws {
        try makeCorrupt("history.json.corrupt-20260101-000000", ageDays: 31)
        try makeCorrupt("presets.json.corrupt-20260101-000000", ageDays: 31)
        try makeCorrupt("notes.corrupt-1", ageDays: 31)
        try makeCorrupt("history.json.corrupt-2026", ageDays: 31)
        let result = MaintenanceSweep.run(referencedBackupPaths: [], historyLoaded: true,
                                          backupDirectory: backups, appSupportDirectory: root)
        XCTAssertEqual(result.corruptFilesRemoved, 2)
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("notes.corrupt-1").path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("history.json.corrupt-2026").path))
        XCTAssertTrue(MaintenanceSweep.isQuarantineFileName("history.json.corrupt-20260904-181500"))
        XCTAssertFalse(MaintenanceSweep.isQuarantineFileName(".json.corrupt-20260904-181500"))
        XCTAssertFalse(MaintenanceSweep.isQuarantineFileName("history.json.corrupt-2026090-1815000"))
    }

}
