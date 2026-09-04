import AppKit

enum AssetStoreError: LocalizedError {
    case unreadableImage(URL)
    case encodingFailed
    case unreadableData

    var errorDescription: String? {
        switch self {
        case .unreadableImage(let url): return String(localized: "画像を読み込めません: \(url.lastPathComponent)")
        case .encodingFailed:           return String(localized: "画像の保存に失敗しました")
        case .unreadableData:           return String(localized: "画像を読み込めません")
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

    /// PNG のバイト列をそのまま保存する。長辺が maxSide 以下の有効な PNG は再エンコードせずに書き込み、
    /// それより大きいものだけ store(_:) で縮小・再エンコードする。
    /// パックから取り込んだ画像を「保存済み PNG のバイト列」で重複判定できるようにするため
    /// (再エンコードすると、同じパックをもう一度読み込んでも一致しなくなる)。
    func store(png data: Data) throws -> UUID {
        guard Self.isPNG(data), let rep = NSBitmapImageRep(data: data) else {
            throw AssetStoreError.unreadableData
        }
        if max(rep.pixelsWide, rep.pixelsHigh) <= Int(Self.maxSide) {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let id = UUID()
            try data.write(to: url(for: id), options: .atomic)
            return id
        }
        guard let image = NSImage(data: data) else { throw AssetStoreError.unreadableData }
        return try store(image)
    }

    /// PNG のシグネチャ (89 50 4E 47 0D 0A 1A 0A) で始まるか
    static func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
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

    /// 長辺が maxSide を超えていれば縮小し、常に単一ビットマップ表現の画像を返す。
    /// 縮小元には最大解像度のビットマップ表現を使う (複数解像度を持つ画像の先頭表現が
    /// サムネイルだと、それを縮小元にしてしまい粗い画像が保存されるため)。
    /// 極端な縦横比だと丸め前の短辺が 1px 未満になり BitmapCanvas.draw に弾かれて元画像に
    /// フォールバックしてしまうため、各辺は必ず 1px 以上にクランプする。
    static func downscaled(_ image: NSImage, maxSide: CGFloat) -> NSImage {
        let bestRep = largestBitmapRep(of: image)
        let pixel = bestRep.map { CGSize(width: $0.pixelsWide, height: $0.pixelsHigh) } ?? image.size
        let ratio = min(1, maxSide / max(pixel.width, pixel.height))
        let target = CGSize(width: max(1, (pixel.width * ratio).rounded()),
                             height: max(1, (pixel.height * ratio).rounded()))
        return BitmapCanvas.draw(size: target) { size in
            if let bestRep {
                bestRep.draw(in: NSRect(origin: .zero, size: size))
            } else {
                image.draw(in: NSRect(origin: .zero, size: size),
                           from: NSRect(origin: .zero, size: image.size),
                           operation: .sourceOver, fraction: 1)
            }
        } ?? image
    }

    /// 面積 (pixelsWide * pixelsHigh) が最大のビットマップ表現。無ければ nil
    private static func largestBitmapRep(of image: NSImage) -> NSBitmapImageRep? {
        image.representations
            .compactMap { $0 as? NSBitmapImageRep }
            .max { $0.pixelsWide * $0.pixelsHigh < $1.pixelsWide * $1.pixelsHigh }
    }
}
