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
        let backupDir = iconManager.backupFolder(for: a, fileID: FileIdentity.make(for: a))   // 鍵は同一性 (fileID)
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

    /// 元々カスタムアイコンが無いフォルダは、再適用してもバックアップを作ってはいけない。
    /// 作ってしまうと FolderArt 自身のアイコンが「元のアイコン」として記録され、
    /// リセットで標準アイコンではなく前回の見た目に戻ってしまう
    func testReapplyWithoutOriginalIconNeverBacksUp() async throws {
        let a = try folder("A")
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("2"),
                                    settings: CompositionSettings(), to: [a])

        let task = try XCTUnwrap(history.task(forFolderPath: a.standardizedFileURL.path))
        XCTAssertNil(task.backupPath)
        XCTAssertFalse(iconManager.backupExists(for: a, fileID: FileIdentity.make(for: a)))

        try coordinator.reset(folder: a)
        XCTAssertFalse(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))
    }

    /// 手でカスタムアイコン A を設定したフォルダを再適用しても、バックアップは
    /// 最初の適用で記録した A のままでなければならない (2 回目の適用結果で上書きされない)
    func testReapplyKeepsOriginalBackupFromFirstApply() async throws {
        let a = try folder("A")
        let manual = FolderIconManager(backupDirectory: root.appendingPathComponent("manual"))
        let red = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
        try manual.applyIcon(red, to: a)

        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: CompositionSettings(), to: [a])
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("2"),
                                    settings: CompositionSettings(), to: [a])

        let task = try XCTUnwrap(history.task(forFolderPath: a.standardizedFileURL.path))
        let backupPath = try XCTUnwrap(task.backupPath)
        let backup = try XCTUnwrap(NSImage(contentsOf: URL(fileURLWithPath: backupPath)))
        XCTAssertTrue(TestSupport.contains(color: .red, in: backup))
    }

    /// 初回の適用でバックアップを作った直後に履歴の保存が失敗したら、
    /// そのバックアップも巻き戻して残さない (残すと後の手動アイコンが二度とバックアップされない)
    func testFirstApplyFailureRemovesFreshlyCreatedBackup() async throws {
        let a = try folder("A")
        let manual = FolderIconManager(backupDirectory: root.appendingPathComponent("manual"))
        let red = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .red)
        try manual.applyIcon(red, to: a)

        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let lockedHistory = HistoryStore(storageURL: locked.appendingPathComponent("history.json"))
        let c = ApplyCoordinator(history: lockedHistory, iconManager: iconManager)

        let outcome = await c.apply(overlayImage: overlayImage, overlay: .text("x"),
                                    settings: CompositionSettings(), to: [a])
        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertFalse(iconManager.backupExists(for: a, fileID: FileIdentity.make(for: a)))
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

    /// 巻き戻し先は「FolderArt 適用前の元アイコン」ではなく適用直前のアイコン。
    /// 元アイコンまで戻すと、履歴の行が残っているのに前回の FolderArt アイコンが消えてしまう
    func testHistoryWriteFailureRollsBackToPreviousIcon() async throws {
        let a = try folder("A")
        var settings = CompositionSettings()
        settings.opacity = 1.0   // 合成後の色をそのまま判定できるようにする
        let manual = FolderIconManager(backupDirectory: root.appendingPathComponent("manual"))
        let green = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .green)
        let blue = TestSupport.makeSolidImage(size: CGSize(width: 64, height: 64), color: .blue)

        // 手で付けた元アイコン (緑) → 1 回目の適用 (赤) は成功。この赤が巻き戻し先
        try manual.applyIcon(green, to: a)
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"),
                                    settings: settings, to: [a])

        // 2 回目 (青) は履歴の書き込みに失敗させる
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        let lockedHistory = HistoryStore(storageURL: locked.appendingPathComponent("history.json"))
        let c = ApplyCoordinator(history: lockedHistory, iconManager: iconManager)

        let outcome = await c.apply(overlayImage: blue, overlay: .text("2"), settings: settings, to: [a])

        XCTAssertEqual(outcome.failed.count, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: a.appendingPathComponent("Icon\r").path))
        let icon = NSWorkspace.shared.icon(forFile: a.path)
        XCTAssertTrue(TestSupport.contains(color: .red, in: icon))    // 1 回目のまま
        XCTAssertFalse(TestSupport.contains(color: .blue, in: icon))  // 2 回目は残っていない
        XCTAssertFalse(TestSupport.contains(color: .green, in: icon)) // 元アイコンまでは戻さない
        XCTAssertEqual(history.tasks.count, 1)
    }

    /// 巻き戻しに失敗したときは、新規バックアップが元アイコンを復元できる唯一の手がかりになる
    /// ため消してはいけない。実際の NSWorkspace で巻き戻し失敗を再現するのは難しいため、
    /// 判定ロジック単体 (shouldRemoveFreshBackup) の真理値表で検証する
    /// bookmarkToRecord: 新規作成に成功すればそれを使い、失敗時は既存 (再適用時に引き継いだもの)
    /// を使う。どちらも無ければ空 Data で、適用自体は失敗させない
    func testBookmarkToRecordPrefersNewFallsBackToExisting() {
        let newData = Data([1, 2, 3])
        let existingData = Data([4, 5, 6])
        // 新規作成に成功 → 新しい方を使う
        XCTAssertEqual(ApplyCoordinator.bookmarkToRecord(new: newData, existing: existingData), newData)
        // 新規作成に失敗したが既存のブックマークがある (再適用) → 以前のものを引き継ぐ
        XCTAssertEqual(ApplyCoordinator.bookmarkToRecord(new: nil, existing: existingData), existingData)
        // どちらも無い → 空 Data (適用自体は成功扱いにする)
        XCTAssertEqual(ApplyCoordinator.bookmarkToRecord(new: nil, existing: nil), Data())
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

    /// 履歴の保存に失敗したフォルダはアイコンを戻して失敗にする (フォルダごとに保存するので、失敗はそのフォルダに閉じる)
    func testHistorySaveFailureRollsBackThatFolder() async throws {
        let a = try folder("A"), b = try folder("B")
        let locked = root.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let lockedHistory = HistoryStore(storageURL: locked.appendingPathComponent("history.json"))
        // 履歴の保存だけ失敗させる (history.json をディレクトリにすると書き込みが失敗する)
        try FileManager.default.createDirectory(at: locked.appendingPathComponent("history.json"), withIntermediateDirectories: false)
        let freshIconManager = FolderIconManager(backupDirectory: root.appendingPathComponent("backups"))
        let c = ApplyCoordinator(history: lockedHistory, iconManager: freshIconManager)

        let outcome = await c.apply(overlayImage: overlayImage, overlay: .text("x"),
                                    settings: CompositionSettings(), to: [a, b])
        XCTAssertTrue(outcome.succeeded.isEmpty)
        XCTAssertEqual(outcome.failed.count, 2)
        XCTAssertTrue(outcome.failed.allSatisfy { $0.reason.contains("履歴の保存に失敗") })
        for f in [a, b] {
            XCTAssertFalse(FileManager.default.fileExists(atPath: f.appendingPathComponent("Icon\r").path))
        }
        // どちらも新規フォルダ (元のバックアップ無し) だったので、巻き戻し成功後は
        // 今回新たに作ったバックアップが消えているはず (使われないまま残ってはいけない)
        XCTAssertFalse(freshIconManager.backupExists(for: a, fileID: FileIdentity.make(for: a)))
        XCTAssertFalse(freshIconManager.backupExists(for: b, fileID: FileIdentity.make(for: b)))
        XCTAssertTrue(lockedHistory.tasks.isEmpty)
    }

    func testShouldRemoveFreshBackupTruthTable() {
        // 新規バックアップがあり、巻き戻しにも成功 → もう不要なので消してよい
        XCTAssertTrue(ApplyCoordinator.shouldRemoveFreshBackup(createdBackup: true, rollbackSucceeded: true))
        // 新規バックアップはあるが巻き戻しに失敗 → 元アイコンの唯一の手がかりなので残す
        XCTAssertFalse(ApplyCoordinator.shouldRemoveFreshBackup(createdBackup: true, rollbackSucceeded: false))
        // 新規に作っていない (既存バックアップを引き継いだだけ) → 何もしない
        XCTAssertFalse(ApplyCoordinator.shouldRemoveFreshBackup(createdBackup: false, rollbackSucceeded: true))
        XCTAssertFalse(ApplyCoordinator.shouldRemoveFreshBackup(createdBackup: false, rollbackSucceeded: false))
    }

    /// 改名・移動したフォルダも fileID で見つけてリセットできる (履歴の行は古い path のまま)
    func testResetByFolderFindsRenamedFolderViaFileID() async throws {
        let a = try folder("A")
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("x"),
                                    settings: CompositionSettings(), to: [a])
        XCTAssertEqual(history.tasks.count, 1)
        let moved = root.appendingPathComponent("A-moved")
        try FileManager.default.moveItem(at: a, to: moved)
        try coordinator.reset(folder: moved)
        XCTAssertTrue(history.tasks.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: moved.appendingPathComponent("Icon\r").path))
    }


    /// 同じ実体のフォルダを実パスとシンボリックリンクの両方で渡しても適用は 1 回、履歴も 1 行
    /// (2 回目に進むと 1 回目が付けたアイコンを「元のアイコン」としてバックアップしてしまう)
    func testSameFolderViaSymlinkIsAppliedOnce() async throws {
        let a = try folder("A")
        let link = root.appendingPathComponent("A-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        let outcome = await coordinator.apply(overlayImage: overlayImage, overlay: .text("x"),
                                              settings: CompositionSettings(), to: [a, link])
        XCTAssertEqual(outcome.succeeded.count, 1)
        XCTAssertTrue(outcome.failed.isEmpty)
        XCTAssertEqual(history.tasks.count, 1)
        XCTAssertNil(history.tasks.first?.backupPath)   // 元は標準アイコンなのでバックアップは無いまま
    }


    /// 適用済みのフォルダを移動した後、同じ場所に別のフォルダ (自前のカスタムアイコン付き) を作って適用しても、
    /// 移動したフォルダのバックアップを拾わず、自分のバックアップを新しく取る
    func testNewFolderAtVacatedPathGetsItsOwnBackup() async throws {
        let a = try folder("A")
        let red = TestSupport.makeSolidImage(size: CGSize(width: 32, height: 32), color: .red)
        XCTAssertTrue(NSWorkspace.shared.setIcon(red, forFile: a.path, options: []))
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("1"), settings: CompositionSettings(), to: [a])
        let movedRow = try XCTUnwrap(history.tasks.first)
        let movedBackup = try XCTUnwrap(movedRow.backupPath)

        let b = root.appendingPathComponent("B")
        try FileManager.default.moveItem(at: a, to: b)
        let newA = try folder("A")
        let blue = TestSupport.makeSolidImage(size: CGSize(width: 32, height: 32), color: .blue)
        XCTAssertTrue(NSWorkspace.shared.setIcon(blue, forFile: newA.path, options: []))
        _ = await coordinator.apply(overlayImage: overlayImage, overlay: .text("2"), settings: CompositionSettings(), to: [newA])

        XCTAssertEqual(history.tasks.count, 2)
        let newRow = try XCTUnwrap(history.tasks.first { $0.fileID != movedRow.fileID })
        let newBackup = try XCTUnwrap(newRow.backupPath)
        XCTAssertNotEqual(newBackup, movedBackup)
        XCTAssertTrue(FileManager.default.fileExists(atPath: movedBackup))
        XCTAssertTrue(FileManager.default.fileExists(atPath: newBackup))
        NSWorkspace.shared.setIcon(nil, forFile: b.path, options: [])
    }



}
