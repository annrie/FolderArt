import XCTest
import AppKit
@testable import FolderArt

final class PackTests: XCTestCase {
    private var dir: URL!
    private var assets: AssetStore!

    override func setUp() {
        super.setUp()
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("PackTests_\(UUID().uuidString)")
        assets = AssetStore(directory: dir)
    }
    override func tearDown() { try? FileManager.default.removeItem(at: dir); super.tearDown() }

    private func makePresets() throws -> [Preset] {
        let id = try assets.store(TestSupport.makeSolidImage(size: CGSize(width: 40, height: 20), color: .red))
        var badge = CompositionSettings(); badge.position = .badge
        return [
            Preset(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings()),
            Preset(name: "26", overlay: .text("26"), settings: badge),
            Preset(name: "ロゴ", overlay: .image(assetID: id), settings: CompositionSettings()),
        ]
    }

    func testRoundTripKeepsEntriesAndEmbedsImage() throws {
        let presets = try makePresets()
        let data = try PackWriter.write(presets, assets: assets, appVersion: "1.3.0")
        let pack = try PackReader.read(data)
        XCTAssertEqual(pack.format, Pack.currentFormat)
        XCTAssertEqual(pack.app, "FolderArt")
        XCTAssertEqual(pack.appVersion, "1.3.0")
        XCTAssertEqual(pack.presets.map(\.name), ["星", "26", "ロゴ"])
        XCTAssertEqual(pack.presets[1].settings.position, .badge)
        XCTAssertNil(pack.presets[0].image)
        let png = try Data(contentsOf: assets.url(for: presets[2].overlay.assetID!))
        XCTAssertEqual(pack.presets[2].image, png)
        // id と createdAt は書き出さない
        let json = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(json.contains("createdAt"))
        XCTAssertFalse(json.contains("\"id\""))
    }

    func testRejectsUnsupportedFormat() throws {
        let data = try PackWriter.write([], assets: assets, appVersion: "1.3.0")
        let bumped = String(decoding: data, as: UTF8.self).replacingOccurrences(of: "\"format\" : 1", with: "\"format\" : 2")
        XCTAssertThrowsError(try PackReader.read(bumped.data(using: .utf8)!)) { error in
            guard case PackError.unsupportedFormat(2) = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsCorruptJSON() {
        XCTAssertThrowsError(try PackReader.read("not json".data(using: .utf8)!)) { error in
            guard case PackError.corrupted = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsTooManyPresets() throws {
        let many = (0..<201).map { PackEntry(name: "p\($0)", overlay: .text("\($0)"), settings: CompositionSettings(), image: nil) }
        let data = try encode(pack(many))
        XCTAssertThrowsError(try PackReader.read(data)) { error in
            guard case PackError.tooManyPresets(201) = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsImagePresetWithoutOrInvalidImage() throws {
        var pack = Pack(format: 1, app: "FolderArt", appVersion: "1.3.0", exportedAt: Date(),
                        presets: [PackEntry(name: "x", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: nil)])
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.missingImage("x") = error else { return XCTFail("\(error)") }
        }
        pack.presets[0].image = "not a png".data(using: .utf8)
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.invalidImage("x") = error else { return XCTFail("\(error)") }
        }
        // PNG 以外の画像形式 (TIFF) も拒否する
        pack.presets[0].image = TestSupport.makeSolidImage(size: CGSize(width: 4, height: 4), color: .red).tiffRepresentation
        XCTAssertThrowsError(try PackReader.read(try encoder.encode(pack))) { error in
            guard case PackError.invalidImage("x") = error else { return XCTFail("\(error)") }
        }
    }

    // MARK: - 検証 (範囲外の設定・サイズ上限・書き出し件数)

    private func pack(_ entries: [PackEntry]) -> Pack {
        Pack(format: 1, app: "FolderArt", appVersion: "1.3.0", exportedAt: Date(), presets: entries)
    }
    private func encode(_ pack: Pack) throws -> Data {
        let encoder = JSONEncoder(); encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(pack)
    }

    func testRejectsOutOfRangeSettings() throws {
        var huge = CompositionSettings(); huge.scale = 1e308
        var tint = CompositionSettings(); tint.tintColor = CodableColor(red: 2, green: 0, blue: 0, alpha: 1)
        var low = CompositionSettings(); low.verticalOffset = -0.5
        for (label, settings) in [("scale", huge), ("tint", tint), ("offset", low)] {
            let data = try encode(pack([PackEntry(name: label, overlay: .text("x"), settings: settings, image: nil)]))
            XCTAssertThrowsError(try PackReader.read(data), label) { error in
                guard case PackError.invalidSettings(label) = error else { return XCTFail("\(label): \(error)") }
            }
        }
        // 境界値はそのまま通る
        var edge = CompositionSettings(); edge.scale = 0.2; edge.opacity = 1.0; edge.verticalOffset = -0.4
        XCTAssertNoThrow(try PackReader.read(try encode(pack([PackEntry(name: "ok", overlay: .text("x"), settings: edge, image: nil)]))))
    }

    func testRejectsLegacyImageOverlay() throws {
        let data = try encode(pack([PackEntry(name: "old", overlay: .legacyImage(name: "x.png"), settings: CompositionSettings(), image: nil)]))
        XCTAssertThrowsError(try PackReader.read(data)) { error in
            guard case PackError.invalidSettings("old") = error else { return XCTFail("\(error)") }
        }
    }

    func testRejectsOversizedImageAndFile() throws {
        // 画像は PNG 判定の前にバイト数で弾く
        let big = Data(count: PackReader.maxImageBytes + 1)
        let data = try encode(pack([PackEntry(name: "big", overlay: .image(assetID: UUID()), settings: CompositionSettings(), image: big)]))
        XCTAssertThrowsError(try PackReader.read(data)) { error in
            guard case PackError.imageTooLarge("big") = error else { return XCTFail("\(error)") }
        }
        // ファイル全体は JSON を読む前にサイズで弾く
        XCTAssertThrowsError(try PackReader.read(Data(count: PackReader.maxFileBytes + 1))) { error in
            guard case PackError.fileTooLarge = error else { return XCTFail("\(error)") }
        }
    }

    func testWriterRejectsTooManyPresets() throws {
        let many = (0..<201).map { Preset(name: "p\($0)", overlay: .text("\($0)"), settings: CompositionSettings()) }
        XCTAssertThrowsError(try PackWriter.write(many, assets: assets, appVersion: "1.3.0")) { error in
            guard case PackError.tooManyPresets(201) = error else { return XCTFail("\(error)") }
        }
    }


    /// 画像が欠けているお気に入りは、どれが原因か分かるエラーで書き出しを止める
    func testWriterNamesThePresetWhoseImageIsMissing() throws {
        let broken = Preset(name: "欠け", overlay: .image(assetID: UUID()), settings: CompositionSettings())
        XCTAssertThrowsError(try PackWriter.write([broken], assets: assets, appVersion: "1.3.0")) { error in
            guard case PackError.assetUnavailable("欠け") = error else { return XCTFail("\(error)") }
        }
    }

}
