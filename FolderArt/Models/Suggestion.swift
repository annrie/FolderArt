import Foundation

/// フォルダ名や中身から導いた候補 1 つ。
struct Suggestion: Equatable, Identifiable {
    enum Kind: Equatable {
        case symbol(String)
        case emoji(String)
        case text(String)
        case preset(Preset)
        /// 中身の代表画像 (等価判定は url + 更新日時。サムネイルは比較しない)
        case image(RepresentativeImage)
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
        // 同じ path の画像が更新されて再走査されたら別の id になり、チップの .task(id:) が描き直す
        case .image(let r):  return "image:\(r.url.path):\(r.modificationDate.timeIntervalSince1970)"
        }
    }
}
