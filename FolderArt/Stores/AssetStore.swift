import AppKit

enum AssetStoreError: LocalizedError {
    case unreadableImage(URL)
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return String(localized: "画像を読み込めません: \(url.lastPathComponent)")
        case .encodingFailed:           return String(localized: "画像の保存に失敗しました")
        }
    }
}

/// オーバーレイ画像を 512px 以下の PNG としてアプリ領域に複製して保持する。
final class AssetStore {
    let directory: URL
    static let maxSide: CGFloat = 512

    convenience init() {
        self.init(directory: HistoryStore.appSupportDirectory.appendingPathComponent("assets"))
    }

    init(directory: URL) {
        self.directory = directory
    }

    func url(for id: UUID) -> URL {
        directory.appendingPathComponent("\(id.uuidString).png")
    }

    func store(contentsOf sourceURL: URL) throws -> UUID {
        guard let image = NSImage(contentsOf: sourceURL) else {
            throw AssetStoreError.unreadableImage(sourceURL)
        }
        return try store(image)
    }

    func store(_ image: NSImage) throws -> UUID {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let resized = Self.downscaled(image, maxSide: Self.maxSide)
        guard let rep = resized.representations.compactMap({ $0 as? NSBitmapImageRep }).first,
              let png = rep.representation(using: .png, properties: [:]) else {
            throw AssetStoreError.encodingFailed
        }
        let id = UUID()
        try png.write(to: url(for: id), options: .atomic)
        return id
    }

    func image(for id: UUID) -> NSImage? {
        NSImage(contentsOf: url(for: id))
    }

    func remove(_ id: UUID) throws {
        let target = url(for: id)
        if FileManager.default.fileExists(atPath: target.path) {
            try FileManager.default.removeItem(at: target)
        }
    }

    func allIDs() -> Set<UUID> {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        return Set(names.compactMap { name in
            name.hasSuffix(".png") ? UUID(uuidString: String(name.dropLast(4))) : nil
        })
    }

    /// 参照されていない PNG を削除し、削除数を返す
    @discardableResult
    func reap(keeping referenced: Set<UUID>) throws -> Int {
        var count = 0
        for id in allIDs().subtracting(referenced) {
            try remove(id)
            count += 1
        }
        return count
    }

    /// 長辺が maxSide を超えていれば縮小し、常に単一ビットマップ表現の画像を返す
    static func downscaled(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let pixel = pixelSize(of: image)
        let ratio = min(1, maxSide / max(pixel.width, pixel.height))
        let target = CGSize(width: (pixel.width * ratio).rounded(), height: (pixel.height * ratio).rounded())
        return BitmapCanvas.draw(size: target) { size in
            image.draw(in: NSRect(origin: .zero, size: size),
                       from: NSRect(origin: .zero, size: image.size),
                       operation: .sourceOver, fraction: 1)
        } ?? image
    }

    private static func pixelSize(of image: NSImage) -> CGSize {
        if let rep = image.representations.first {
            return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
        }
        return image.size
    }
}
