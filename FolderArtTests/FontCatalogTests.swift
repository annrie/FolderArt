import XCTest
import AppKit
@testable import FolderArt

final class FontCatalogTests: XCTestCase {

    func testNilFamilyIsSystemRounded() {
        let font = FontCatalog.font(family: nil, weight: .bold, size: 100, families: [])
        XCTAssertTrue(font.fontName.contains("Rounded"), font.fontName)
    }

    func testKnownFamilyResolvesToNearestWeight() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Sans"), "Hiragino Sans is not installed")
        let regular = FontCatalog.font(family: "Hiragino Sans", weight: .regular, size: 100)
        let bold = FontCatalog.font(family: "Hiragino Sans", weight: .bold, size: 100)
        let black = FontCatalog.font(family: "Hiragino Sans", weight: .black, size: 100)
        XCTAssertEqual(regular.familyName, "Hiragino Sans")
        XCTAssertEqual(regular.fontName, "HiraginoSans-W3")
        XCTAssertEqual(bold.fontName, "HiraginoSans-W6")
        XCTAssertEqual(black.fontName, "HiraginoSans-W8")
    }

    func testSingleWeightFamilyIgnoresWeight() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Maru Gothic ProN"), "Hiragino Maru Gothic ProN is not installed")
        for weight in FontWeightValue.allCases {
            XCTAssertEqual(FontCatalog.font(family: "Hiragino Maru Gothic ProN", weight: weight, size: 100).fontName, "HiraMaruProN-W4", "\(weight)")
        }
    }

    func testUnknownFamilyFallsBackToSystemRounded() {
        let font = FontCatalog.font(family: "No Such Family XYZ", weight: .bold, size: 100, families: [])
        XCTAssertTrue(font.fontName.contains("Rounded"), font.fontName)
    }

    func testPostScriptNameStillResolvesForOldPacks() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Sans"), "Hiragino Sans is not installed")
        // families に無い名前は NSFont(name:) の経路 (1.3.0 までのパックに PostScript 名が入っていた場合の互換)
        let font = FontCatalog.font(family: "HiraginoSans-W6", weight: .regular, size: 100)
        XCTAssertEqual(font.fontName, "HiraginoSans-W6")
    }

    func testAvailableKeepsDefaultAndDropsMissingFamilies() {
        let list = FontCatalog.available(families: ["Menlo"])
        XCTAssertEqual(list.map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.available(families: []).map(\.family), [nil])
        XCTAssertEqual(FontCatalog.choices.count, 8)
        XCTAssertNil(FontCatalog.choices.first?.family)
    }

    func testChoicesIncludingUnknownCurrentAppendsOther() {
        let base = FontCatalog.available(families: ["Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: nil, available: base).map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: "Menlo", available: base).map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: "Zapfino", available: base).map(\.family), [nil, "Menlo", "Zapfino"])
        XCTAssertEqual(FontCatalog.choices(including: "Zapfino", available: base).last?.id, "Zapfino")
    }

    func testWeightDisplayNamesAreDistinct() {
        // LocalizedStringKey は比較しにくいので、描画に使う NSFont.Weight が 6 種で異なることだけ見る
        XCTAssertEqual(Set(FontWeightValue.allCases.map(\.nsWeight.rawValue)).count, 6)
    }
}
