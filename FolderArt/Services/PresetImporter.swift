import Foundation

enum PresetImporter {
    /// パックをお気に入りに取り込む。重複は「既存 + このパックで追加を決めた項目」に対して判定。
    /// 画像は AssetStore に新しい ID で複製し、保存に失敗したら複製した PNG を消す。
    static func importPack(_ pack: Pack, into store: PresetStore, assets: AssetStore) throws -> ImportSummary {
        var staged: [Preset] = []
        var createdAssets: [UUID] = []
        var skipped = 0

        // 画像プリセットは assetID が違うので、PNG のバイト列で同一性を判定する。
        // パックの画像は AssetStore にバイト列のまま保存する (store(png:)) ので、
        // 保存済みファイルのバイト列と entry.image をそのまま比較できる。
        // 既存のお気に入りの PNG は項目ごとに読み直さず、1 回読んだら使い回す (項目 × お気に入りの総当たりになるため)
        var pngCache: [UUID: Data?] = [:]
        func pngData(of preset: Preset) -> Data? {
            guard let id = preset.overlay.assetID else { return nil }
            if let cached = pngCache[id] { return cached }
            let data = try? Data(contentsOf: assets.url(for: id))
            pngCache[id] = data
            return data
        }
        // 512px を超える画像は AssetStore.store(png:) が縮小・再エンコードするため、そのようなパックを
        // もう一度読み込んでもバイト列が一致せず重複判定をすり抜ける。FolderArt が書き出すパックの画像は
        // 常に 512px 以下なので、手で作ったパックだけの制限として受け入れている
        func isIdentical(_ entry: PackEntry, _ p: Preset) -> Bool {
            guard p.settings == entry.settings else { return false }
            if entry.overlay.assetID != nil {
                guard let image = entry.image else { return false }
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
                    guard let data = entry.image, PackReader.isPNG(data) else {
                        throw PackError.invalidImage(entry.name)
                    }
                    let id = try assets.store(png: data)
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
