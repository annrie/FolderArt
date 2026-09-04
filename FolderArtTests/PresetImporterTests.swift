import XCTest
import AppKit
@testable import FolderArt

final class PresetImporterTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!
    private var store: PresetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ImporterTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir.appendingPathComponent("assets"))
        store = PresetStore(storageURL: dir.appendingPathComponent("presets.json"))
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func pack(_ entries: [PackEntry]) -> Pack {
        Pack(format: 1, app: "FolderArt", appVersion: "1.3.0", exportedAt: Date(), presets: entries)
    }
    private func png() -> Data { TestSupport.pngData(TestSupport.makeSolidImage(size: CGSize(width: 8, height: 8), color: .green)) }

    func testAddsEntriesAndRenamesDuplicates() throws {
        try store.add(name: "星", overlay: .text("x"), settings: CompositionSettings())
        let summary = try PresetImporter.importPack(pack([
            PackEntry(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings(), image: nil),
            PackEntry(name: "月", overlay: .emoji("🌙"), settings: CompositionSettings(), image: nil),
        ]), into: store, assets: assets)
        XCTAssertEqual(summary, ImportSummary(added: 2, skippedIdentical: 0))
        XCTAssertEqual(store.presets.map(\.name), ["星 2", "月", "星"])
    }

    func testSkipsIdenticalAgainstExistingAndWithinPack() throws {
        try store.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        let e = PackEntry(name: "star", overlay: .symbol(name: "star.fill"), settings: CompositionSettings(), image: nil)
        let summary = try PresetImporter.importPack(pack([e, e, PackEntry(name: "月", overlay: .emoji("🌙"), settings: CompositionSettings(), image: nil)]),
                                                    into: store, assets: assets)
        XCTAssertEqual(summary, ImportSummary(added: 1, skippedIdentical: 2))
        XCTAssertEqual(store.presets.map(\.name), ["月", "星"])
    }

    func testIdenticalImageEntriesAreSkippedByPixels() throws {
        let entry = PackEntry(name: "ロゴ", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: png())
        let first = try PresetImporter.importPack(pack([entry, entry]), into: store, assets: assets)
        XCTAssertEqual(first, ImportSummary(added: 1, skippedIdentical: 1))
        // 同じパックをもう一度読み込んでも増えない (既存のお気に入りの PNG と一致)
        let second = try PresetImporter.importPack(pack([entry]), into: store, assets: assets)
        XCTAssertEqual(second, ImportSummary(added: 0, skippedIdentical: 1))
        XCTAssertEqual(assets.allIDs().count, 1)
    }

    func testImageEntryIsCopiedIntoAssetsWithNewID() throws {
        let stale = UUID()
        let summary = try PresetImporter.importPack(pack([
            PackEntry(name: "ロゴ", overlay: .image(assetID: stale), settings: CompositionSettings(), image: png()),
        ]), into: store, assets: assets)
        XCTAssertEqual(summary.added, 1)
        let id = try XCTUnwrap(store.presets.first?.overlay.assetID)
        XCTAssertNotEqual(id, stale)
        XCTAssertNotNil(assets.image(for: id))
    }

    func testFailedSaveLeavesNoAssetsBehind() throws {
        let locked = dir.appendingPathComponent("locked")
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        let lockedStore = PresetStore(storageURL: locked.appendingPathComponent("presets.json"))
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: locked.path)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path) }
        XCTAssertThrowsError(try PresetImporter.importPack(pack([
            PackEntry(name: "ロゴ", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: png()),
        ]), into: lockedStore, assets: assets))
        XCTAssertTrue(lockedStore.presets.isEmpty)
        XCTAssertTrue(assets.allIDs().isEmpty)
    }
}
