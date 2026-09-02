import Foundation
import Combine

final class PresetStore: ObservableObject {
    @Published private(set) var presets: [Preset] = []
    private(set) var loadError: Error?

    private let store: CodableStore<[Preset]>

    convenience init() {
        self.init(storageURL: HistoryStore.appSupportDirectory.appendingPathComponent("presets.json"))
    }

    init(storageURL: URL) {
        store = CodableStore(fileURL: storageURL)
        do {
            presets = try store.load() ?? []
        } catch {
            loadError = error
            presets = []
        }
    }

    @discardableResult
    func add(name: String?, overlay: Overlay, settings: CompositionSettings) throws -> Preset {
        let resolvedName = (name?.isEmpty == false) ? name! : Self.defaultName(for: overlay, existing: presets)
        let preset = Preset(name: resolvedName, overlay: overlay, settings: settings)
        var updated = presets
        updated.insert(preset, at: 0)
        try store.save(updated)
        presets = updated
        return preset
    }

    func rename(_ preset: Preset, to name: String) throws {
        var updated = presets
        guard let i = updated.firstIndex(where: { $0.id == preset.id }) else { return }
        updated[i].name = name
        try store.save(updated)
        presets = updated
    }

    func remove(_ preset: Preset) throws {
        let updated = presets.filter { $0.id != preset.id }
        try store.save(updated)
        presets = updated
    }

    var referencedAssetIDs: Set<UUID> {
        Set(presets.compactMap { $0.overlay.assetID })
    }

    /// "star.fill", "star.fill 2", "star.fill 3" … と重複しない名前を作る
    static func defaultName(for overlay: Overlay, existing: [Preset]) -> String {
        let base = overlay.displayName.isEmpty ? String(localized: "お気に入り") : overlay.displayName
        let names = Set(existing.map(\.name))
        if !names.contains(base) { return base }
        var n = 2
        while names.contains("\(base) \(n)") { n += 1 }
        return "\(base) \(n)"
    }
}
