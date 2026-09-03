import XCTest
@testable import FolderArt

final class OverlayTests: XCTestCase {

    func testRoundTripAllCases() throws {
        let id = UUID()
        let cases: [Overlay] = [
            .image(assetID: id), .symbol(name: "star.fill"), .emoji("🎵"),
            .text("2026"), .legacyImage(name: "old.png")
        ]
        for overlay in cases {
            let data = try JSONEncoder().encode(overlay)
            let decoded = try JSONDecoder().decode(Overlay.self, from: data)
            XCTAssertEqual(decoded, overlay)
        }
    }

    func testDisplayNameAndFlags() {
        let id = UUID()
        XCTAssertEqual(Overlay.symbol(name: "star.fill").displayName, "star.fill")
        XCTAssertEqual(Overlay.emoji("🎵").displayName, "🎵")
        XCTAssertEqual(Overlay.text("2026").displayName, "2026")
        XCTAssertEqual(Overlay.legacyImage(name: "old.png").displayName, "old.png")
        XCTAssertEqual(Overlay.image(assetID: id).assetID, id)
        XCTAssertNil(Overlay.symbol(name: "x").assetID)
        XCTAssertFalse(Overlay.legacyImage(name: "old.png").canReapply)
        XCTAssertTrue(Overlay.text("a").canReapply)
    }

    func testOnlyImagesFillTheFolderWhenClipped() {
        XCTAssertTrue(Overlay.image(assetID: UUID()).fillsFolderWhenClipped)
        XCTAssertTrue(Overlay.legacyImage(name: "x").fillsFolderWhenClipped)
        XCTAssertFalse(Overlay.symbol(name: "star.fill").fillsFolderWhenClipped)
        XCTAssertFalse(Overlay.emoji("🎵").fillsFolderWhenClipped)
        XCTAssertFalse(Overlay.text("26").fillsFolderWhenClipped)
    }
}
