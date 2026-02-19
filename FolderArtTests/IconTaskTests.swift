import XCTest
@testable import FolderArt

final class IconTaskTests: XCTestCase {

    func testIconTaskIsEncodableAndDecodable() throws {
        let task = IconTask(
            folderPath: "/Users/test/Documents",
            bookmarkData: Data(),
            appliedAt: Date(timeIntervalSince1970: 1000),
            backupPath: "/backups/test/original.png",
            imageName: "photo.png",
            position: .center,
            scale: 0.6,
            opacity: 0.9
        )

        let data = try JSONEncoder().encode(task)
        let decoded = try JSONDecoder().decode(IconTask.self, from: data)

        XCTAssertEqual(decoded.folderPath, task.folderPath)
        XCTAssertEqual(decoded.imageName, task.imageName)
        XCTAssertEqual(decoded.position, .center)
        XCTAssertEqual(decoded.scale, 0.6)
        XCTAssertEqual(decoded.opacity, 0.9)
    }

    func testIconPositionHasTwoCases() {
        let center = IconPosition.center
        let badge = IconPosition.badge
        XCTAssertNotEqual(center, badge)
    }
}
