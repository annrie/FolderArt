import XCTest
import AppKit
@testable import FolderArt

final class QuickActionProviderTests: XCTestCase {
    func testFolderURLsFromPasteboardExtractsFileURLs() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QA_\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let pb = NSPasteboard(name: .init("QATest_\(UUID())"))
        pb.clearContents()
        pb.writeObjects([dir as NSURL])
        let urls = QuickActionProvider.folderURLs(from: pb)
        XCTAssertEqual(urls.map { $0.standardizedFileURL }, [dir.standardizedFileURL])
    }

    func testFolderURLsFromEmptyPasteboardIsEmpty() {
        let pb = NSPasteboard(name: .init("QATestEmpty_\(UUID())"))
        pb.clearContents()
        XCTAssertTrue(QuickActionProvider.folderURLs(from: pb).isEmpty)
    }
}
