import AppKit

enum PackReader {
    /// JSON を読み、形式・件数・画像を検証する。1 件でも不正ならパック全体を拒否。
    static func read(_ data: Data) throws -> Pack {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // format だけ先に見て、未対応なら「新しいバージョン」と伝える
        struct Header: Decodable { let format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw PackError.corrupted }
        guard header.format == Pack.currentFormat else { throw PackError.unsupportedFormat(header.format) }
        guard let pack = try? decoder.decode(Pack.self, from: data) else { throw PackError.corrupted }
        guard pack.presets.count <= PackWriter.maxPresets else { throw PackError.tooManyPresets(pack.presets.count) }
        for entry in pack.presets where entry.overlay.assetID != nil {
            guard let image = entry.image else { throw PackError.missingImage(entry.name) }
            guard isPNG(image), NSImage(data: image) != nil else { throw PackError.invalidImage(entry.name) }
        }
        return pack
    }

    /// PNG のシグネチャ (89 50 4E 47 0D 0A 1A 0A) で始まるか。パックの画像は PNG だけを受け付ける
    static func isPNG(_ data: Data) -> Bool {
        data.count >= 8 && data.prefix(8).elementsEqual([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
    }
}
