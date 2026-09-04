import Foundation
import Combine

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []
    private(set) var loadError: Error?

    private let store: CodableStore<[Preset]>
    /// 壊れたファイルを退避してから保存する必要があるか (最初の保存で 1 回だけ)
    private var needsQuarantine = false

    convenience init() {
        self.init(storageURL: HistoryStore.appSupportDirectory.appendingPathComponent("presets.json"))
    }

    init(storageURL: URL) {
        store = CodableStore(fileURL: storageURL)
        do {
            presets = try store.load() ?? []
        } catch {
            loadError = error
            needsQuarantine = true   // 読めなかった中身を次の保存で黙って消さない
            presets = []
        }
    }

    @discardableResult
    func add(name: String?, overlay: Overlay, settings: CompositionSettings) throws -> Preset {
        let resolvedName = (name?.isEmpty == false) ? name! : Self.defaultName(for: overlay, existing: presets)
        let preset = Preset(name: resolvedName, overlay: overlay, settings: settings)
        var updated = presets
        updated.insert(preset, at: 0)
        try save(updated)
        presets = updated
        return preset
    }

    /// 複数件を先頭に順序どおり挿入し、保存は 1 回。保存に失敗したら 1 件も入らない。
    func addAll(_ newPresets: [Preset]) throws {
        guard !newPresets.isEmpty else { return }
        let updated = newPresets + presets
        try save(updated)
        presets = updated
    }

    func rename(_ preset: Preset, to name: String) throws {
        var updated = presets
        guard let i = updated.firstIndex(where: { $0.id == preset.id }) else { return }
        updated[i].name = name
        try save(updated)
        presets = updated
    }

    func remove(_ preset: Preset) throws {
        let updated = presets.filter { $0.id != preset.id }
        try save(updated)
        presets = updated
    }

    /// 読み込みに失敗していた場合、最初の保存の前に壊れたファイルを退避する
    private func save(_ updated: [Preset]) throws {
        if needsQuarantine {
            try store.quarantineIfPresent()
            needsQuarantine = false
        }
        try store.save(updated)
    }

    var referencedAssetIDs: Set<UUID> {
        Set(presets.compactMap { $0.overlay.assetID })
    }

    /// "star.fill", "star.fill 2", "star.fill 3" … と重複しない名前を作る
    static func defaultName(for overlay: Overlay, existing: [Preset]) -> String {
        defaultName(forProposed: overlay.displayName, existing: existing)
    }

    /// proposed をそのまま、重なれば "proposed 2", "proposed 3" … にする
    static func defaultName(forProposed proposed: String, existing: [Preset]) -> String {
        let base = proposed.isEmpty ? String(localized: "お気に入り") : proposed
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
