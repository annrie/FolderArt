import Foundation

enum PackWriter {
    static let maxPresets = 200

    /// maxBytes は読み込み側の上限 (PackReader.maxFileBytes)。超えるパックを書き出しても読み戻せないので、ここで失敗にする
    static func write(_ presets: [Preset], assets: AssetStore, appVersion: String,
                      maxBytes: Int = PackReader.maxFileBytes) throws -> Data {
        // 読み込み側と同じ上限。超えたまま書き出すと、自分で作ったパックを読み戻せなくなる
        guard presets.count <= maxPresets else { throw PackError.tooManyPresets(presets.count) }
        let entries: [PackEntry] = try presets.map { preset in
            // 読み込み側と同じ長さの上限 (手元のお気に入りは UI で制限していないので、ここで確かめる)
            guard PackReader.fieldsWithinLimits(name: preset.name, overlay: preset.overlay, settings: preset.settings) else {
                throw PackError.invalidSettings(String(preset.name.prefix(PackReader.maxNameLength)))
            }
            var image: Data?
            if let id = preset.overlay.assetID {
                // 画像が欠けているお気に入りは、どれが原因か分かる形で書き出しを止める
                guard let data = try? Data(contentsOf: assets.url(for: id)) else { throw PackError.assetUnavailable(preset.name) }
                image = data
            }
            return PackEntry(name: preset.name, overlay: preset.overlay, settings: preset.settings, image: image)
        }
        let pack = Pack(format: Pack.currentFormat, app: "FolderArt", appVersion: appVersion,
                        exportedAt: Date(), presets: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(pack)
        guard data.count <= maxBytes else { throw PackError.fileTooLarge }
        return data
    }
}
