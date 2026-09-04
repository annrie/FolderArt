import XCTest
@testable import FolderArt

final class IconTaskTests: XCTestCase {

    func testV2RoundTrip() throws {
        let task = IconTask(
            folderPath: "/Users/test/Documents",
            bookmarkData: Data([1, 2, 3]),
            appliedAt: Date(timeIntervalSince1970: 1000),
            backupPath: nil,
            overlay: .symbol(name: "star.fill"),
            settings: CompositionSettings(position: .badge, scale: 0.5, opacity: 0.8)
        )
        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(IconTask.self, from: data)
        XCTAssertEqual(decoded, task)
        XCTAssertEqual(decoded.version, IconTask.currentVersion)
    }

    func testV1JSONMigratesToLegacyImage() throws {
        // 1.0.1 が書いていた形式 (version 欄なし、設定が平置き)
        let json = """
        {"id":"6E3A0C4E-3F2B-4C4B-9D1B-7B7B4E5D1A11","folderPath":"/tmp/a",
         "bookmarkData":"","appliedAt":1000,"backupPath":"","imageName":"photo.png",
         "position":"badge","scale":0.5,"opacity":0.8,"verticalOffset":0.1,"clipToFolderShape":false}
        """.data(using: .utf8)!
        let task = try JSONDecoder().decode(IconTask.self, from: json)
        XCTAssertEqual(task.version, IconTask.currentVersion)
        XCTAssertEqual(task.folderPath, "/tmp/a")
        XCTAssertEqual(task.overlay, .legacyImage(name: "photo.png"))
        XCTAssertNil(task.backupPath)                       // "" は nil に正規化
        XCTAssertEqual(task.settings.position, .badge)
        XCTAssertEqual(task.settings.scale, 0.5)
        XCTAssertEqual(task.settings.verticalOffset, 0.1)
        XCTAssertFalse(task.settings.clipToFolderShape)
        XCTAssertEqual(task.settings.tintColor, .white)     // 新規欄は初期値
    }

    func testIconPositionHasTwoCases() {
        XCTAssertEqual(IconPosition.allCases.count, 2)
    }

    func testFileIDRoundTripsAndDefaultsToNil() throws {
        let task = IconTask(folderPath: "/x", bookmarkData: Data(), backupPath: nil,
                            overlay: .text("1"), settings: CompositionSettings(), fileID: "vol:42")
        let data = try JSONEncoder().encode(task)
        XCTAssertEqual(try JSONDecoder().decode(IconTask.self, from: data).fileID, "vol:42")
        let json = """
        {"version":2,"id":"6E3A0C4E-3F2B-4C4B-9D1B-7B7B4E5D1A11","folderPath":"/x","bookmarkData":"","appliedAt":0,
         "overlay":{"text":{"_0":"1"}},"settings":{}}
        """.data(using: .utf8)!
        XCTAssertNil(try JSONDecoder().decode(IconTask.self, from: json).fileID)
    }
}
