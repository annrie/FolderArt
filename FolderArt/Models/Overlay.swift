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

    /// 切り抜き ON + 中央のとき、フォルダ全体に敷き詰めるか (画像だけ true)。
    /// 記号・絵文字・文字はサイズ指定どおりに置き、フォルダの形からはみ出す部分だけを切り抜く。
    var fillsFolderWhenClipped: Bool {
        switch self {
        case .image, .legacyImage: return true
        case .symbol, .emoji, .text: return false
        }
    }

    /// 文字・絵文字は空白だけだと描けない (OverlayRenderer が trim して nil を返す)。パックの検証で使う
    var hasRenderablePayload: Bool {
        switch self {
        case .text(let s), .emoji(let s): return !s.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .symbol(let name):           return !name.isEmpty
        case .image, .legacyImage:        return true
        }
    }

    var canReapply: Bool {
        if case .legacyImage = self { return false }
        return true
    }
}
