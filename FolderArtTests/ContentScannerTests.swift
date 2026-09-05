import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import FolderArt

final class ContentScannerTests: XCTestCase {
    private var root: URL!

    override func setUp() async throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ContentScannerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - helpers

    @discardableResult
    private func touch(_ name: String, in dir: URL? = nil, date: Date? = nil) throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        try Data().write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    /// 実際に復号できる PNG (単色)
    @discardableResult
    private func png(_ name: String, size: CGSize = CGSize(width: 64, height: 32), in dir: URL? = nil, date: Date? = nil) throws -> URL {
        let image = TestSupport.makeSolidImage(size: size, color: .red)
        let data = try XCTUnwrap(TestSupport.bitmap(of: image).representation(using: .png, properties: [:]))
        let url = (dir ?? root).appendingPathComponent(name)
        try data.write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    /// EXIF の向き (orientation 6 = 90 度回転) を付けた JPEG
    private func rotatedJPEG(_ name: String, size: CGSize) throws -> URL {
        let image = TestSupport.makeSolidImage(size: size, color: .blue)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let url = root.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func pixelSize(ofPNG data: Data) throws -> CGSize {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    // MARK: - classify

    func testClassifyFollowsPriorityOrder() {
        XCTAssertEqual(ContentKind.classify(type: nil, isDirectory: true, isPackage: false), .folder)
        XCTAssertEqual(ContentKind.classify(type: .application, isDirectory: true, isPackage: true), .app)
        XCTAssertEqual(ContentKind.classify(type: .png, isDirectory: false, isPackage: false), .image)
        XCTAssertEqual(ContentKind.classify(type: .mpeg4Movie, isDirectory: false, isPackage: false), .video)
        XCTAssertEqual(ContentKind.classify(type: .mp3, isDirectory: false, isPackage: false), .audio)
        XCTAssertEqual(ContentKind.classify(type: .pdf, isDirectory: false, isPackage: false), .pdf)
        XCTAssertEqual(ContentKind.classify(type: .presentation, isDirectory: false, isPackage: false), .presentation)
        XCTAssertEqual(ContentKind.classify(type: .spreadsheet, isDirectory: false, isPackage: false), .spreadsheet)
        XCTAssertEqual(ContentKind.classify(type: .swiftSource, isDirectory: false, isPackage: false), .code)   // .text より先
        XCTAssertEqual(ContentKind.classify(type: .plainText, isDirectory: false, isPackage: false), .document)
        XCTAssertEqual(ContentKind.classify(type: .zip, isDirectory: false, isPackage: false), .archive)
        XCTAssertNil(ContentKind.classify(type: .data, isDirectory: false, isPackage: false))
        XCTAssertNil(ContentKind.classify(type: nil, isDirectory: false, isPackage: false))
    }

    func testDominantPrefersEarlierKindOnTie() {
        XCTAssertEqual(ContentSummary.dominant(of: [.image: 2, .document: 2]), .image)
        XCTAssertEqual(ContentSummary.dominant(of: [.document: 3, .audio: 2]), .document)
        XCTAssertNil(ContentSummary.dominant(of: [:]))
        XCTAssertNil(ContentSummary.dominant(of: [.image: 0]))
    }

    // MARK: - scan

    func testCountsByKindAndPicksDominantWithRepresentative() throws {
        try png("a.png"); try png("b.png"); try png("c.png")
        try touch("notes.txt"); try touch("song.mp3")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.image: 3, .document: 1, .audio: 1])
        XCTAssertEqual(summary.dominant, .image)
        XCTAssertNotNil(summary.representative)
    }

    func testHiddenFilesAndIconFileAreSkipped() throws {
        try png(".hidden.png")
        try touch(ContentScanner.iconFileName)
        try touch("readme.md")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.document: 1])
        XCTAssertNil(summary.representative)
    }

    func testSubfoldersCountAsFolderAndGiveNoRepresentative() throws {
        for name in ["one", "two", "three"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try png("x.png")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.folder: 3, .image: 1])
        XCTAssertEqual(summary.dominant, .folder)
        XCTAssertNil(summary.representative)
    }

    func testRepresentativeIsNewestThenByName() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        try png("a.png", date: old)
        try png("c.png", date: new)
        try png("b.png", date: new)
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        let rep = try XCTUnwrap(summary.representative)
        XCTAssertEqual(rep.url.lastPathComponent, "b.png")
        XCTAssertEqual(rep.modificationDate, new)
    }

    func testRepresentativeSkipsUnsupportedFormatsAndHugeFiles() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        try png("ok.png", date: old)
        try touch("newer.psd", date: new)   // 画像には数えるが代表にはしない (パネルで選べる形式ではない)
        var summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts[.image], 2)
        XCTAssertEqual(summary.representative?.url.lastPathComponent, "ok.png")

        // 上限を下げると ok.png も代表にならない (種類の多数派はそのまま)
        summary = try XCTUnwrap(ContentScanner.scan(root, maxImageBytes: 10))
        XCTAssertEqual(summary.dominant, .image)
        XCTAssertNil(summary.representative)
    }

    func testLimitStopsEnumeration() throws {
        for i in 0..<5 { try touch("f\(i).txt") }
        let summary = try XCTUnwrap(ContentScanner.scan(root, limit: 3))
        XCTAssertEqual(summary.counts.values.reduce(0, +), 3)
    }

    func testMissingFolderIsNil() {
        XCTAssertNil(ContentScanner.scan(root.appendingPathComponent("does-not-exist")))
    }

    func testEmptyFolderIsEmptySummary() throws {
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertTrue(summary.counts.isEmpty)
        XCTAssertNil(summary.dominant)
    }

    func testCancelledTaskGivesNil() async throws {
        try touch("a.txt")
        let folder: URL = root
        let task = Task.detached { () -> ContentSummary? in
            try? await Task.sleep(nanoseconds: 200_000_000)   // cancel 済みなら即座に抜ける
            return ContentScanner.scan(folder)
        }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    // MARK: - thumbnail

    func testThumbnailIsAtMost256AndKeepsAspect() throws {
        let url = try png("wide.png", size: CGSize(width: 800, height: 400))
        let data = try XCTUnwrap(ContentScanner.thumbnailPNG(of: url))
        XCTAssertEqual(try pixelSize(ofPNG: data), CGSize(width: 256, height: 128))
        XCTAssertTrue(AssetStore.isPNG(data))
    }

    func testThumbnailAppliesExifOrientation() throws {
        let url = try rotatedJPEG("rotated.jpg", size: CGSize(width: 400, height: 200))
        let data = try XCTUnwrap(ContentScanner.thumbnailPNG(of: url))
        let size = try pixelSize(ofPNG: data)
        XCTAssertGreaterThan(size.height, size.width, "\(size)")
    }

    func testThumbnailOfNonImageIsNil() throws {
        let url = try touch("x.txt")
        XCTAssertNil(ContentScanner.thumbnailPNG(of: url))
    }
}
