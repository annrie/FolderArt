import XCTest
@testable import FolderArt

final class LastPresetStoreTests: XCTestCase {
    private var dir: URL!
    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("LastPresetStoreTests_\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func url() -> URL { dir.appendingPathComponent("last-preset.json") }

    func testAbsentFileReadsNil() {
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }

    func testRoundTripsAcrossInstances() throws {
        let id = UUID()
        let a = LastPresetStore(storageURL: url())
        try a.save(id)
        let b = LastPresetStore(storageURL: url())
        XCTAssertEqual(b.id, id)
    }

    func testSettingNilClearsIt() throws {
        let a = LastPresetStore(storageURL: url())
        try a.save(UUID())
        try a.save(nil)
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }

    func testCorruptFileReadsNil() throws {
        try "not json".data(using: .utf8)!.write(to: url())
        XCTAssertNil(LastPresetStore(storageURL: url()).id)
    }
}
