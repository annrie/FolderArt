import AppKit

enum PackReader {
    /// パックファイル全体の上限。これより大きいファイルは JSON を読む前に拒否する
    static let maxFileBytes = 100 * 1024 * 1024
    /// 項目ごとの PNG の上限。512px 以下の PNG は AssetStore にそのまま保存するので、ここで抑える
    static let maxImageBytes = 8 * 1024 * 1024

    /// JSON を読み、形式・件数・設定の範囲・画像を検証する。1 件でも不正ならパック全体を拒否。
    /// 検証は PNG を 1 枚も保存する前に全項目に対して行う (PresetImporter は検証済みの Pack を受け取る)。
    static func read(_ data: Data) throws -> Pack {
        guard data.count <= maxFileBytes else { throw PackError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // format だけ先に見て、未対応なら「新しいバージョン」と伝える
        struct Header: Decodable { let format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw PackError.corrupted }
        guard header.format == Pack.currentFormat else { throw PackError.unsupportedFormat(header.format) }
        guard let pack = try? decoder.decode(Pack.self, from: data) else { throw PackError.corrupted }
        guard pack.presets.count <= PackWriter.maxPresets else { throw PackError.tooManyPresets(pack.presets.count) }
        for entry in pack.presets {
            // 手で書き換えたパックの範囲外の値 (scale 1e308、色 2.0、NaN など) をそのまま保存すると、
            // サムネイル描画で毎回失敗して起動のたびに問題になるので、ここで弾く
            guard entry.settings.isValid, entry.overlay.canReapply else { throw PackError.invalidSettings(entry.name) }
            guard entry.overlay.assetID != nil else { continue }
            guard let image = entry.image else { throw PackError.missingImage(entry.name) }
            guard image.count <= maxImageBytes else { throw PackError.imageTooLarge(entry.name) }
            guard isPNG(image), NSImage(data: image) != nil else { throw PackError.invalidImage(entry.name) }
        }
        return pack
    }

    /// パックの画像は PNG だけを受け付ける (シグネチャ判定は AssetStore に集約)
    static func isPNG(_ data: Data) -> Bool {
        AssetStore.isPNG(data)
    }
}
