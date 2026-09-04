import AppKit

enum PresetImporter {
    /// パックをお気に入りに取り込む。重複は「既存 + このパックで追加を決めた項目」に対して判定。
    /// 画像は AssetStore に新しい ID で複製し、保存に失敗したら複製した PNG を消す。
    static func importPack(_ pack: Pack, into store: PresetStore, assets: AssetStore) throws -> ImportSummary {
        var staged: [Preset] = []
        var createdAssets: [UUID] = []
        var skipped = 0

        // 画像プリセットは assetID が違うので、PNG のバイト列で同一性を判定する
        func pngData(of preset: Preset) -> Data? {
            preset.overlay.assetID.flatMap { try? Data(contentsOf: assets.url(for: $0)) }
        }
        func isIdentical(_ entry: PackEntry, _ p: Preset) -> Bool {
            guard p.settings == entry.settings else { return false }
            if let image = entry.image, entry.overlay.assetID != nil {
                return p.overlay.assetID != nil && pngData(of: p) == image
            }
            return p.overlay == entry.overlay
        }

        do {
            for entry in pack.presets {
                if (store.presets + staged).contains(where: { isIdentical(entry, $0) }) {
                    skipped += 1
                    continue
                }
                var overlay = entry.overlay
                if entry.overlay.assetID != nil {
                    guard let data = entry.image, PackReader.isPNG(data), let image = NSImage(data: data) else {
                        throw PackError.invalidImage(entry.name)
                    }
                    let id = try assets.store(image)
                    createdAssets.append(id)
                    overlay = .image(assetID: id)
                }
                let name = PresetStore.defaultName(forProposed: entry.name, existing: store.presets + staged)
                staged.append(Preset(name: name, overlay: overlay, settings: entry.settings))
            }
            try store.addAll(staged)
        } catch {
            for id in createdAssets { try? assets.remove(id) }
            throw error
        }
        return ImportSummary(added: staged.count, skippedIdentical: skipped)
    }
}
