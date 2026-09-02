import XCTest
import AppKit
@testable import FolderArt

final class AssetStoreTests: XCTestCase {
    private var dir: URL!
    private var store: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("AssetStoreTests_\(UUID().uuidString)")
        store = AssetStore(directory: dir)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
        super.tearDown()
    }

    func testStoreWritesPNGAndReadsBack() throws {
        let image = TestSupport.makeSolidImage(size: CGSize(width: 100, height: 60), color: .red)
        let id = try store.store(image)
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.url(for: id).path))
        let loaded = try XCTUnwrap(store.image(for: id))
        XCTAssertEqual(TestSupport.pixelSize(of: loaded), CGSize(width: 100, height: 60))
        XCTAssertTrue(TestSupport.contains(color: .red, in: loaded))
    }

    func testLargeImageIsDownscaledTo512() throws {
        let image = TestSupport.makeSolidImage(size: CGSize(width: 2048, height: 1024), color: .blue)
        let id = try store.store(image)
        let loaded = try XCTUnwrap(store.image(for: id))
        XCTAssertEqual(TestSupport.pixelSize(of: loaded), CGSize(width: 512, height: 256))
    }

    func testStoreFromFileURL() throws {
        let src = dir.appendingPathComponent("src.png")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 10, height: 10), color: .green)).write(to: src)
        let id = try store.store(contentsOf: src)
        XCTAssertNotNil(store.image(for: id))
        XCTAssertThrowsError(try store.store(contentsOf: dir.appendingPathComponent("missing.png")))
    }

    func testRemoveAndReap() throws {
        let a = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        let b = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        let c = try store.store(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .red))
        XCTAssertEqual(store.allIDs(), [a, b, c])
        try store.remove(a)
        XCTAssertEqual(store.allIDs(), [b, c])
        let removed = try store.reap(keeping: [b])
        XCTAssertEqual(removed, 1)
        XCTAssertEqual(store.allIDs(), [b])
    }
}
