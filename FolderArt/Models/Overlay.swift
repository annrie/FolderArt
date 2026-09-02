import Foundation

/// フォルダアイコンに重ねるもの。
enum Overlay: Codable, Equatable, Hashable, Sendable {
    case image(assetID: UUID)       // AssetStore 内の PNG
    case symbol(name: String)       // SF Symbols 名
    case emoji(String)
    case text(String)
    case legacyImage(name: String)  // v1 履歴の移行専用。再適用不可

    /// 履歴やお気に入りに表示する短い名前
    var displayName: String {
        switch self {
        case .image:                   return String(localized: "画像")
        case .symbol(let name):        return name
        case .emoji(let s):            return s
        case .text(let s):             return s
        case .legacyImage(let name):   return name
        }
    }

    var assetID: UUID? {
        if case .image(let id) = self { return id }
        return nil
    }

    var canReapply: Bool {
        if case .legacyImage = self { return false }
        return true
    }
}
