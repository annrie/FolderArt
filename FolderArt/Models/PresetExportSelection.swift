import Foundation

/// 「選んで書き出す」の選択状態。お気に入りのリストは持たず ID だけを持つ純粋な値型。
/// 件数や書き出す配列は常に今のお気に入り (`selected(from:)`) から数える。初期状態は未選択
struct PresetExportSelection: Equatable {
    private(set) var selectedIDs: Set<UUID> = []

    mutating func toggle(_ id: UUID) {
        if selectedIDs.contains(id) { selectedIDs.remove(id) } else { selectedIDs.insert(id) }
    }

    mutating func selectAll(_ presets: [Preset]) {
        selectedIDs = Set(presets.map(\.id))
    }

    mutating func clear() {
        selectedIDs = []
    }

    func isSelected(_ id: UUID) -> Bool {
        selectedIDs.contains(id)
    }

    /// 帯の順を保つ。今のお気に入りに無い ID は無視する
    func selected(from presets: [Preset]) -> [Preset] {
        presets.filter { selectedIDs.contains($0.id) }
    }

    /// お気に入りが増減したら呼ぶ。今のお気に入りに無い ID を捨てる
    mutating func prune(to presets: [Preset]) {
        selectedIDs.formIntersection(presets.map(\.id))
    }
}
