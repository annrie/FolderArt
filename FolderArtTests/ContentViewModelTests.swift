import XCTest
import AppKit
@testable import FolderArt

@MainActor
final class ContentViewModelTests: XCTestCase {

    private var testFolderURL: URL!

    override func setUp() {
        super.setUp()
        testFolderURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("VMTest_\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: testFolderURL, withIntermediateDirectories: true)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: testFolderURL)
        super.tearDown()
    }

    func testInitialStateIsEmpty() {
        let vm = ContentViewModel()
        XCTAssertNil(vm.selectedFolderURL)
        XCTAssertNil(vm.selectedImage)
        XCTAssertNil(vm.previewImage)
        XCTAssertFalse(vm.canApply)
    }

    func testCanApplyBecomeTrueWhenBothSelected() {
        let vm = ContentViewModel()
        vm.selectedFolderURL = testFolderURL
        vm.selectedImage = NSImage(size: CGSize(width: 10, height: 10))
        XCTAssertTrue(vm.canApply)
    }

    func testUpdatePreviewGeneratesImage() {
        let vm = ContentViewModel()
        vm.selectedFolderURL = testFolderURL

        let image = NSImage(size: CGSize(width: 100, height: 100))
        image.lockFocus(); NSColor.blue.setFill()
        NSRect(origin: .zero, size: image.size).fill()
        image.unlockFocus()

        vm.selectedImage = image
        vm.updatePreview()

        XCTAssertNotNil(vm.previewImage)
    }
}
