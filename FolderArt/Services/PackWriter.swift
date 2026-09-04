import Foundation

enum PackWriter {
    static let maxPresets = 200

    static func write(_ presets: [Preset], assets: AssetStore, appVersion: String) throws -> Data {
        let entries: [PackEntry] = try presets.map { preset in
            var image: Data?
            if let id = preset.overlay.assetID {
                image = try Data(contentsOf: assets.url(for: id))
            }
            return PackEntry(name: preset.name, overlay: preset.overlay, settings: preset.settings, image: image)
        }
        let pack = Pack(format: Pack.currentFormat, app: "FolderArt", appVersion: appVersion,
                        exportedAt: Date(), presets: entries)
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(pack)
    }
}
