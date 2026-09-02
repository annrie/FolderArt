import Foundation

/// お気に入り = オーバーレイ + 合成設定 (見た目まるごと)
struct Preset: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    var name: String
    var overlay: Overlay
    var settings: CompositionSettings
    let createdAt: Date

    init(id: UUID = UUID(), name: String, overlay: Overlay,
         settings: CompositionSettings, createdAt: Date = Date()) {
        self.id = id
        self.name = name
        self.overlay = overlay
        self.settings = settings
        self.createdAt = createdAt
    }
}
