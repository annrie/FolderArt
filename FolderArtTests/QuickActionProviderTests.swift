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

    func testFolderURLsExcludesNonDirectories() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("QA_\(UUID())")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("f.txt")
        try "x".data(using: .utf8)!.write(to: file)
        let pb = NSPasteboard(name: .init("QATestFile_\(UUID())"))
        pb.clearContents()
        pb.writeObjects([file as NSURL])
        XCTAssertTrue(QuickActionProvider.folderURLs(from: pb).isEmpty)
    }

    /// コールド起動で保存データが壊れているケースを模す (AppModel.init が起動エラーを立てるが、
    /// お気に入りが無いので applyLastPreset は .noPreset を返す)。既存の起動エラーを
    /// 「まだお気に入りを使っていません…」で上書きしないことを確認する (Codex PR #6 r2)
    @MainActor
    func testApplyLastPresetKeepsExistingErrorMessageOnNoPreset() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("QA_\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("target")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let model = AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("h.json")),
                             presets: PresetStore(storageURL: root.appendingPathComponent("p.json")),
                             assets: AssetStore(directory: root.appendingPathComponent("a")),
                             userDictionaryURL: root.appendingPathComponent("dict/suggestions-user.json"),
                             lastPresetStore: LastPresetStore(storageURL: root.appendingPathComponent("last-preset.json")),
                             runsMaintenance: false)
        let startupError = "既存の起動エラー (テスト用)"
        model.errorMessage = startupError   // お気に入りが無いので、これから呼ぶ applyLastPreset は .noPreset を返すはず

        let provider = QuickActionProvider(model: model)
        let pb = NSPasteboard(name: .init("QATestApply_\(UUID())"))
        pb.clearContents()
        pb.writeObjects([dir as NSURL])

        let finished = XCTestExpectation(description: "onShowWindow")
        provider.onShowWindow = { finished.fulfill() }
        provider.applyLastPreset(pb, userData: nil, error: nil)
        await fulfillment(of: [finished], timeout: 2)

        XCTAssertEqual(model.errorMessage, startupError)   // 上書きされていない
    }
}
