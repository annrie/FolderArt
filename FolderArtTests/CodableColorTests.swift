import XCTest
import AppKit
@testable import FolderArt

final class CodableColorTests: XCTestCase {

    func testRoundTripThroughJSON() throws {
        let color = CodableColor(red: 0.2, green: 0.4, blue: 0.6, alpha: 0.8)
        let data = try JSONEncoder().encode(color)
        let decoded = try JSONDecoder().decode(CodableColor.self, from: data)
        XCTAssertEqual(decoded, color)
    }

    func testConvertsFromAndToNSColor() {
        let original = NSColor(srgbRed: 1.0, green: 0.5, blue: 0.0, alpha: 1.0)
        let codable = CodableColor(original)
        XCTAssertEqual(codable.red, 1.0, accuracy: 0.001)
        XCTAssertEqual(codable.green, 0.5, accuracy: 0.001)
        XCTAssertEqual(codable.blue, 0.0, accuracy: 0.001)

        let back = codable.nsColor.usingColorSpace(.sRGB)!
        XCTAssertEqual(back.redComponent, 1.0, accuracy: 0.001)
        XCTAssertEqual(back.greenComponent, 0.5, accuracy: 0.001)
    }

    func testFontWeightMapsToNSFontWeight() {
        XCTAssertEqual(FontWeightValue.bold.nsWeight, .bold)
        XCTAssertEqual(FontWeightValue.regular.nsWeight, .regular)
        XCTAssertEqual(FontWeightValue.allCases.count, 6)
    }
}
