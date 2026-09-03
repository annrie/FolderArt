import XCTest
@testable import FolderArt

final class BookmarkManagerTests: XCTestCase {

    func testCreateAndResolveBookmark() throws {
        // テスト用の一時ディレクトリを使用
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("FolderArtTest_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        let data = try BookmarkManager.createBookmark(for: tempDir)
        XCTAssertFalse(data.isEmpty)

        let resolved = try BookmarkManager.resolveBookmark(data)
        XCTAssertEqual(resolved.path, tempDir.path)
    }

    func testResolveInvalidBookmarkThrows() {
        let invalidData = Data("invalid".utf8)
        XCTAssertThrowsError(try BookmarkManager.resolveBookmark(invalidData))
    }

    /// 単体テストは FolderArt.app 自身をホストとして実行されるため、FolderArt.entitlements
    /// が app-sandbox を有効にしている以上テストプロセスでも isSandboxed は true になる。
    /// それでも testCreateAndResolveBookmark が通るのは、一時ディレクトリがサンドボックス
    /// コンテナ内にあってセキュリティスコープ付きの作成/解決がそのまま成功するからで、
    /// 非セキュリティスコープのフォールバックには最初から依存していない。
    func testIsSandboxedTrueInHostedTestProcess() {
        XCTAssertTrue(BookmarkManager.isSandboxed)
    }
}
