import XCTest
@testable import FolderArt

final class CompositionSettingsTests: XCTestCase {

    func testDefaultsIncludeWhiteTintAndBoldFont() {
        let s = CompositionSettings()
        XCTAssertEqual(s.tintColor, .white)
        XCTAssertNil(s.fontName)
        XCTAssertEqual(s.fontWeight, .bold)
    }

    func testRoundTripThroughJSON() throws {
        var s = CompositionSettings(position: .badge, scale: 0.4, opacity: 0.7,
                                    verticalOffset: 0.1, clipToFolderShape: false)
        s.tintColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        s.fontWeight = .heavy
        let data = try JSONEncoder().encode(s)
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: data)
        XCTAssertEqual(decoded, s)
    }

    func testDecodingJSONWithoutNewKeysUsesDefaults() throws {
        // 将来キーを足したときの後方互換を保証する
        let json = """
        {"position":"center","scale":0.6,"opacity":0.9,"verticalOffset":-0.04,"clipToFolderShape":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: json)
        XCTAssertEqual(decoded.tintColor, .white)
        XCTAssertEqual(decoded.fontWeight, .bold)
        XCTAssertNil(decoded.fontName)
    }

    // MARK: - 範囲の検証 (パックなど外から来た値に使う)

    func testDefaultsAreValid() {
        XCTAssertTrue(CompositionSettings().isValid)
    }

    func testRangeBoundaries() {
        var s = CompositionSettings()
        s.scale = 0.2;  XCTAssertTrue(s.isValid)
        s.scale = 1.0;  XCTAssertTrue(s.isValid)
        s.scale = 0.19; XCTAssertFalse(s.isValid)
        s.scale = 1.01; XCTAssertFalse(s.isValid)
        s.scale = 1e308; XCTAssertFalse(s.isValid)
        s.scale = .nan; XCTAssertFalse(s.isValid)
        s.scale = .infinity; XCTAssertFalse(s.isValid)

        s = CompositionSettings(); s.opacity = 0.1;  XCTAssertTrue(s.isValid)
        s.opacity = 0.09; XCTAssertFalse(s.isValid)
        s = CompositionSettings(); s.verticalOffset = -0.4; XCTAssertTrue(s.isValid)
        s.verticalOffset = 0.41; XCTAssertFalse(s.isValid)
    }

    func testColorAndFontName() {
        var s = CompositionSettings()
        s.tintColor = CodableColor(red: 1.5, green: 0, blue: 0, alpha: 1); XCTAssertFalse(s.isValid)
        s.tintColor = CodableColor(red: 0.5, green: 0.5, blue: 0.5, alpha: .nan); XCTAssertFalse(s.isValid)
        s.tintColor = CodableColor(red: 0, green: 0, blue: 0, alpha: -0.1); XCTAssertFalse(s.isValid)
        s.tintColor = .black; XCTAssertTrue(s.isValid)
        s.fontName = ""; XCTAssertFalse(s.isValid)
        s.fontName = "Helvetica"; XCTAssertTrue(s.isValid)
    }

    /// スライダーの範囲は CompositionSettings の定数が唯一の定義
    func testSharedRanges() {
        XCTAssertEqual(CompositionSettings.scaleRange, 0.2...1.0)
        XCTAssertEqual(CompositionSettings.opacityRange, 0.1...1.0)
        XCTAssertEqual(CompositionSettings.verticalOffsetRange, -0.4...0.4)
    }
}
