import XCTest
@testable import FolderArt

final class PresetStoreTests: XCTestCase {
    private var url: URL!
    private var store: PresetStore!

    override func setUp() {
        super.setUp()
        url = FileManager.default.temporaryDirectory.appendingPathComponent("presets_\(UUID().uuidString).json")
        store = PresetStore(storageURL: url)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: url)
        super.tearDown()
    }

    func testAddPersistsAndOrdersNewestFirst() throws {
        try store.add(name: "one", overlay: .text("1"), settings: CompositionSettings())
        try store.add(name: "two", overlay: .text("2"), settings: CompositionSettings())
        XCTAssertEqual(store.presets.map(\.name), ["two", "one"])
        let reloaded = PresetStore(storageURL: url)
        XCTAssertEqual(reloaded.presets.map(\.name), ["two", "one"])
    }

    func testAddWithoutNameUsesDefaultName() throws {
        let p = try store.add(name: nil, overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        XCTAssertEqual(p.name, "star.fill")
        let p2 = try store.add(name: nil, overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        XCTAssertEqual(p2.name, "star.fill 2")
    }

    func testRenameAndRemove() throws {
        let p = try store.add(name: "a", overlay: .emoji("🎵"), settings: CompositionSettings())
        try store.rename(p, to: "music")
        XCTAssertEqual(store.presets.first?.name, "music")
        try store.remove(p)
        XCTAssertTrue(store.presets.isEmpty)
    }

    func testReferencedAssetIDs() throws {
        let id = UUID()
        try store.add(name: "img", overlay: .image(assetID: id), settings: CompositionSettings())
        try store.add(name: "txt", overlay: .text("x"), settings: CompositionSettings())
        XCTAssertEqual(store.referencedAssetIDs, [id])
    }

    func testCorruptFileSetsLoadError() throws {
        try "oops".data(using: .utf8)!.write(to: url)
        let s = PresetStore(storageURL: url)
        XCTAssertNotNil(s.loadError)
        XCTAssertTrue(s.presets.isEmpty)
    }

    func testAddAllInsertsInOrderWithOneSave() throws {
        try store.add(name: "old", overlay: .text("o"), settings: CompositionSettings())
        let a = Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())
        let b = Preset(name: "b", overlay: .text("b"), settings: CompositionSettings())
        try store.addAll([a, b])
        XCTAssertEqual(store.presets.map(\.name), ["a", "b", "old"])
        XCTAssertEqual(PresetStore(storageURL: url).presets.map(\.name), ["a", "b", "old"])
    }

    func testAddAllIsAllOrNothing() throws {
        // 保存先を書けなくして addAll → メモリにもファイルにも増えない
        let locked = url.deletingLastPathComponent().appendingPathComponent("locked_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let s = PresetStore(storageURL: locked.appendingPathComponent("presets.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try s.addAll([Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())]))
        XCTAssertTrue(s.presets.isEmpty)
    }
}
