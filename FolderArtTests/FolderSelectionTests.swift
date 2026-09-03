import XCTest
@testable import FolderArt

@MainActor
final class FolderSelectionTests: XCTestCase {
    private var root: URL!
    private var a: URL!, b: URL!, c: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("FolderSelectionTests_\(UUID().uuidString)")
        a = root.appendingPathComponent("A"); b = root.appendingPathComponent("B"); c = root.appendingPathComponent("C")
        for d in [a, b, c] { try FileManager.default.createDirectory(at: d!, withIntermediateDirectories: true) }
    }
    override func tearDown() async throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testAddDedupesAndIgnoresFiles() throws {
        let file = root.appendingPathComponent("file.txt")
        try "x".data(using: .utf8)!.write(to: file)
        let sel = FolderSelection()
        sel.add([a, b, a, file, URL(fileURLWithPath: a.path + "/")])
        XCTAssertEqual(sel.folders.map(\.lastPathComponent), ["A", "B"])
    }

    func testTargetsAreAllWhenNothingSelected() {
        let sel = FolderSelection()
        sel.add([a, b, c])
        XCTAssertEqual(sel.targets.count, 3)
        sel.selectedIDs = [b.standardizedFileURL]
        XCTAssertEqual(sel.targets.map(\.lastPathComponent), ["B"])
        sel.clearSelection()
        XCTAssertEqual(sel.targets.count, 3)
    }

    func testRemoveAlsoClearsSelectionOfThatFolder() {
        let sel = FolderSelection()
        sel.add([a, b])
        sel.selectedIDs = [a.standardizedFileURL, b.standardizedFileURL]
        sel.remove(a)
        XCTAssertEqual(sel.folders.map(\.lastPathComponent), ["B"])
        XCTAssertEqual(sel.selectedIDs, [b.standardizedFileURL])
        sel.removeAll()
        XCTAssertTrue(sel.isEmpty)
        XCTAssertTrue(sel.selectedIDs.isEmpty)
    }
}
