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
        {"position":"center","scale":0.6,"opacity":0.9,"verticalOffset":0.0,"clipToFolderShape":true}
        """.data(using: .utf8)!
        let decoded = try JSONDecoder().decode(CompositionSettings.self, from: json)
        XCTAssertEqual(decoded.tintColor, .white)
        XCTAssertEqual(decoded.fontWeight, .bold)
        XCTAssertNil(decoded.fontName)
    }
}
