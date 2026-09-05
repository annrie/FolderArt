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
        FileWatcher(directory: dir, file: file, debounce: 0.2) {
            XCTAssertTrue(Thread.isMainThread)
            expectation.fulfill()
        }
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
