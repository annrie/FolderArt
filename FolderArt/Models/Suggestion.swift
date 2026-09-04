import Foundation

/// フォルダ名から導いた候補 1 つ。
struct Suggestion: Equatable, Identifiable {
    enum Kind: Equatable {
        case symbol(String)
        case emoji(String)
        case text(String)
        case preset(Preset)
    }

    let kind: Kind
    /// ツールチップ用 (例: 「"photo" に一致」)
    let reason: String

    var id: String {
        switch kind {
        case .symbol(let s): return "symbol:\(s)"
        case .emoji(let s):  return "emoji:\(s)"
        case .text(let s):   return "text:\(s)"
        case .preset(let p): return "preset:\(p.id.uuidString)"
        }
    }
}
