import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class ApplyCoordinatorTests: XCTestCase {
    private var root: URL!
    private var historyURL: URL!
    private var history: HistoryStore!
    private var coordinator: ApplyCoordinator!
    private var overlayImage: NSImage!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ApplyTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        historyURL = root.appendingPathComponent("history.json")
        history = HistoryStore(storageURL: historyURL)
        coordinator = ApplyCoordinator(history: history)
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
}
