import XCTest
@testable import FolderArt

final class CodableStoreTests: XCTestCase {
    private var url: URL!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CodableStoreTests_\(UUID().uuidString)/nested/data.json")
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url.deletingLastPathComponent().deletingLastPathComponent())
        super.tearDown()
    }

    func testLoadReturnsNilWhenFileMissing() throws {
        let store = CodableStore<[String]>(fileURL: url)
        XCTAssertNil(try store.load())
    }

    func testSaveCreatesDirectoriesAndRoundTrips() throws {
        let store = CodableStore<[String]>(fileURL: url)
        try store.save(["a", "b"])
        XCTAssertEqual(try store.load(), ["a", "b"])
    }

    func testCorruptFileThrows() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        let store = CodableStore<[String]>(fileURL: url)
        XCTAssertThrowsError(try store.load())
    }

    func testQuarantineRenamesExistingFile() throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "not json".data(using: .utf8)!.write(to: url)
        let store = CodableStore<[String]>(fileURL: url)

        let moved = try XCTUnwrap(try store.quarantineIfPresent())

        XCTAssertFalse(FileManager.default.fileExists(atPath: url.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: moved.path))
        XCTAssertTrue(moved.lastPathComponent.hasPrefix("data.json.corrupt-"), moved.lastPathComponent)
        XCTAssertEqual(try String(contentsOf: moved), "not json")
    }

    func testQuarantineReturnsNilWhenFileMissing() throws {
        let store = CodableStore<[String]>(fileURL: url)
        XCTAssertNil(try store.quarantineIfPresent())
    }
}
