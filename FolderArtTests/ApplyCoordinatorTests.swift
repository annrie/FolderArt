import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class ApplyCoordinatorTests: XCTestCase {
    private var root: URL!
    private var historyURL: URL!
    private var history: HistoryStore!
    private var coordinator: ApplyCoordinator!
    private var iconManager: FolderIconManager!
    private var overlayImage: NSImage!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ApplyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        historyURL = root.appendingPathComponent("history.json")
        history = HistoryStore(storageURL: historyURL)
        // 本物の Application Support を汚さないよう、バックアップ先はテンポラリに逃がす
        iconManager = FolderIconManager(backupDirectory: root.appendingPathComponent("backups"))
        coordinator = ApplyCoordinator(history: history, iconManager: iconManager)
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

    /// 履歴に無いフォルダ (手でカスタムアイコンを設定したもの) のリセットは何もしない
    func testResetIgnoresFolderWithoutHistoryRow() throws {
        let a = try folder("A")
        let manual = FolderIconManager(backupDirectory: root.appendingPathComponent("manual"))
        try manual.applyIcon(overlayImage, to: a)
        let iconFile = a.appendingPathComponent("Icon\r")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconFile.path))

        try coordinator.reset(folder: a)

        XCTAssertTrue(FileManager.default.fileExists(atPath: iconFile.path))
        try manual.resetIcon(for: a, backupURL: nil)
    }

    /// リセット対象のフォルダが既に削除されていたら reset は失敗し、履歴の行は消さずに残す。
    /// reset(_ task:) はブックマーク解決自体が失敗して先に throw するため検証にならない
    /// (それは元々ある挙動)。resetIcon の失敗を確かめるには reset(folder:) を使う。
    func testResetFolderThrowsAndKeepsHistoryWhenFolderIsGone() async throws {
        let a = try folder("A")
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        try FileManager.default.removeItem(at: a)

        XCTAssertThrowsError(try coordinator.reset(folder: a))
        XCTAssertEqual(history.tasks.count, 1)
    }

    /// リセット後もバックアップが残っていると、その後ユーザーが手で別のカスタムアイコンを
    /// 付けて再適用したときに古い方が「元のアイコン」として使い回されてしまう
    func testResetDiscardsBackupSoNextApplyRecordsCurrentIcon() async throws {
        let a = try folder("A")
        let manual = FolderIconManager(backupDirectory: root.appendingPathComponent("manual"))
        let red = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
        let blue = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .blue)

        // 手でアイコン A (赤) を設定 → 適用 → リセット
        try manual.applyIcon(red, to: a)
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        let backupDir = iconManager.backupFolder(for: a)
        XCTAssertTrue(FileManager.default.fileExists(atPath: backupDir.path))

        try coordinator.reset(folder: a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: backupDir.path))

        // 手でアイコン B (青) を設定 → 再適用したら B が新しい「元のアイコン」になる
        try manual.applyIcon(blue, to: a)
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("2"),
                                    settings: CompositionSettings(), to: [a])
        let backup = try XCTUnwrap(NSImage(contentsOf: backupDir.appendingPathComponent("original.png")))
        XCTAssertTrue(TestSupport.contains(color: .blue, in: backup))
        XCTAssertFalse(TestSupport.contains(color: .red, in: backup))
    }

    func testHistoryWriteFailureRollsBackIcon() async throws {
        let a = try folder("A")
        // history.json を書き込み不可のディレクトリに置く → upsert が throw する
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let lockedHistory = HistoryStore(storageURL: locked.appendingPathComponent("history.json"))
        let c = ApplyCoordinator(history: lockedHistory, iconManager: iconManager)

        let outcome = await c.apply(overlayImage: overlayImage, overlay: .text("x"),
                                    settings: CompositionSettings(), to: [a])
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertTrue(outcome.succeeded.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))
        XCTAssertTrue(lockedHistory.tasks.isEmpty)
    }
}
