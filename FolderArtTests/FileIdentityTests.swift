import XCTest
@testable import FolderArt

final class FileIdentityTests: XCTestCase {
    func testSameFolderSameIDAndSurvivesRename() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileIdentity_\(UUID().uuidString)")
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let id1 = try XCTUnwrap(FileIdentity.make(for: a))
        XCTAssertTrue(id1.contains(":"))
        XCTAssertEqual(FileIdentity.make(for: a), id1)

        let b = root.appendingPathComponent("B")
        try FileManager.default.moveItem(at: a, to: b)
        XCTAssertEqual(FileIdentity.make(for: b), id1)           // 同一ボリューム内の改名で不変

        let c = root.appendingPathComponent("C")
        try FileManager.default.createDirectory(at: c, withIntermediateDirectories: true)
        XCTAssertNotEqual(FileIdentity.make(for: c), id1)
        XCTAssertNil(FileIdentity.make(for: root.appendingPathComponent("missing")))
    }

    /// シンボリックリンク経由でも同じフォルダは同じ ID (attributesOfItem はリンク自身を見るので解決してから取る)
    func testSymlinkResolvesToTheSameIdentity() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("FileIdentity_\(UUID().uuidString)")
        let a = root.appendingPathComponent("A")
        try FileManager.default.createDirectory(at: a, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let link = root.appendingPathComponent("A-link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: a)
        XCTAssertNotNil(FileIdentity.make(for: a))
        XCTAssertEqual(FileIdentity.make(for: link), FileIdentity.make(for: a))
    }

}
