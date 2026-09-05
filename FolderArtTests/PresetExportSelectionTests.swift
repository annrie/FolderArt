import XCTest
@testable import FolderArt

final class PresetExportSelectionTests: XCTestCase {
    private let a = Preset(name: "a", overlay: .text("a"), settings: CompositionSettings())
    private let b = Preset(name: "b", overlay: .text("b"), settings: CompositionSettings())
    private let c = Preset(name: "c", overlay: .text("c"), settings: CompositionSettings())

    func testToggleFlips() {
        var s = PresetExportSelection()
        XCTAssertFalse(s.isSelected(a.id))
        s.toggle(a.id)
        XCTAssertTrue(s.isSelected(a.id))
        s.toggle(a.id)
        XCTAssertFalse(s.isSelected(a.id))
    }

    func testSelectAllAndClear() {
        var s = PresetExportSelection()
        s.selectAll([a, b, c])
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "b", "c"])
        s.clear()
        XCTAssertTrue(s.selected(from: [a, b, c]).isEmpty)
    }

    func testSelectedKeepsStripOrderAndIgnoresUnknownIDs() {
        var s = PresetExportSelection()
        s.toggle(c.id); s.toggle(a.id)
        s.toggle(UUID())   // 存在しない ID
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "c"])
        XCTAssertEqual(s.selected(from: [c, b, a]).map(\.name), ["c", "a"])
    }

    func testPruneDropsIDsNoLongerPresent() {
        var s = PresetExportSelection()
        s.selectAll([a, b, c])
        s.prune(to: [a, c])
        XCTAssertEqual(s.selectedIDs, [a.id, c.id])
        XCTAssertEqual(s.selected(from: [a, b, c]).map(\.name), ["a", "c"])
    }
}
