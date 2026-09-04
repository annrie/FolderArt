import AppKit

enum PackReader {
    /// パックファイル全体の上限。これより大きいファイルは JSON を読む前に拒否する
    static let maxFileBytes = 100 * 1024 * 1024
    /// 項目ごとの PNG の上限。512px 以下の PNG は AssetStore にそのまま保存するので、ここで抑える
    static let maxImageBytes = 8 * 1024 * 1024
    /// 復号後の画素数の上限 (4096×4096)。圧縮率の高い PNG で巨大な寸法を宣言されても、復号する前に弾く
    static let maxImagePixels = 4096 * 4096
    /// 文字・絵文字の長さ (書記素数) の上限。1 行のラベルなので十分。巨大な文字列を保存してレイアウトで固まらないようにする
    static let maxTextLength = 100
    static let maxEmojiLength = 8
    /// お気に入りの名前の長さ (書記素数) の上限。保存と表示のたびに巨大な文字列を扱わないようにする
    static let maxNameLength = 100

    /// 書記素数だけでなく UTF-8 のバイト数も見る (1 文字に結合文字を大量に付けると書記素数は 1 のまま巨大になる)。
    /// 1 書記素あたり最大 16 バイトまで許す (絵文字の連結や異体字セレクタを含めても十分)
    static func withinLimit(_ s: String, graphemes: Int) -> Bool {
        s.count <= graphemes && s.utf8.count <= graphemes * 16
    }

    /// 文字・絵文字の長さが上限内か (他の種類は常に true)
    static func payloadWithinLimits(_ overlay: Overlay) -> Bool {
        switch overlay {
        case .text(let s):  return withinLimit(s, graphemes: maxTextLength)
        case .emoji(let s): return withinLimit(s, graphemes: maxEmojiLength)
        default:            return true
        }
    }

    /// 名前・文字・絵文字・フォント名の長さが全て上限内か。読み込みと書き出しの両方で同じ規則を使う
    /// (書き出せるのに読み戻せないパックを作らない)
    static func fieldsWithinLimits(name: String, overlay: Overlay, settings: CompositionSettings) -> Bool {
        withinLimit(name, graphemes: maxNameLength)
            && payloadWithinLimits(overlay)
            && withinLimit(settings.fontName ?? "", graphemes: maxNameLength)
    }

    /// PNG の IHDR (先頭チャンク) から宣言された (幅, 高さ) を読む。PNG でなければ nil
    static func pngDimensions(_ data: Data) -> (width: Int, height: Int)? {
        guard isPNG(data), data.count >= 24 else { return nil }
        let base = data.startIndex
        func be32(_ offset: Int) -> Int { data[base + offset ..< base + offset + 4].reduce(0) { ($0 << 8) | Int($1) } }
        guard Array(data[base + 12 ..< base + 16]) == Array("IHDR".utf8) else { return nil }
        return (be32(16), be32(20))
    }

    /// JSON を読み、形式・件数・設定の範囲・画像を検証する。1 件でも不正ならパック全体を拒否。
    /// 検証は PNG を 1 枚も保存する前に全項目に対して行う (PresetImporter は検証済みの Pack を受け取る)。
    /// symbolCatalog を渡すと、記号がこの macOS に (制限付きでなく) 存在することも確かめる
    /// (新しい macOS で作ったパックの記号は古い環境では描けないため)
    static func read(_ data: Data, symbolCatalog: SymbolCatalog? = nil) throws -> Pack {
        guard data.count <= maxFileBytes else { throw PackError.fileTooLarge }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        // format だけ先に見て、未対応なら「新しいバージョン」と伝える
        struct Header: Decodable { let format: Int }
        guard let header = try? decoder.decode(Header.self, from: data) else { throw PackError.corrupted }
        guard header.format == Pack.currentFormat else { throw PackError.unsupportedFormat(header.format) }
        guard let pack = try? decoder.decode(Pack.self, from: data) else { throw PackError.corrupted }
        guard pack.presets.count <= PackWriter.maxPresets else { throw PackError.tooManyPresets(pack.presets.count) }
        for entry in pack.presets {
            // 手で書き換えたパックの範囲外の値 (scale 1e308、色 2.0、NaN など) をそのまま保存すると、
            // サムネイル描画で毎回失敗して起動のたびに問題になるので、ここで弾く
            guard entry.settings.isValid, entry.overlay.canReapply, entry.overlay.hasRenderablePayload,
                  fieldsWithinLimits(name: entry.name, overlay: entry.overlay, settings: entry.settings) else {
                throw PackError.invalidSettings(String(entry.name.prefix(maxNameLength)))
            }
            if let catalog = symbolCatalog, case .symbol(let name) = entry.overlay, !catalog.contains(name) {
                throw PackError.symbolUnavailable(entry.name, name)
            }
            guard entry.overlay.assetID != nil else { continue }
            guard let image = entry.image else { throw PackError.missingImage(entry.name) }
            guard image.count <= maxImageBytes else { throw PackError.imageTooLarge(entry.name) }
            guard let size = pngDimensions(image) else { throw PackError.invalidImage(entry.name) }
            // 宣言された寸法で先に弾く (NSImage に渡すと復号後のビットマップを丸ごと確保するため)
            // 乗算は UInt32 の最大値同士でオーバーフローするので、割り算で比較する
            guard size.width > 0, size.height > 0, size.width <= maxImagePixels / size.height else {
                throw PackError.imageTooLarge(entry.name)
            }
            guard NSImage(data: image) != nil else { throw PackError.invalidImage(entry.name) }
        }
        return pack
    }

    /// パックの画像は PNG だけを受け付ける (シグネチャ判定は AssetStore に集約)
    static func isPNG(_ data: Data) -> Bool {
        AssetStore.isPNG(data)
    }
}
