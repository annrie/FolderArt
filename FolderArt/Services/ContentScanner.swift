import AppKit
import ImageIO
import UniformTypeIdentifiers

/// フォルダ直下のファイルの種類。判定と多数派の同数の優先順はこの列挙順
enum ContentKind: CaseIterable, Hashable, Sendable {
    case image, video, audio, pdf, presentation, spreadsheet, code, document, archive, app, folder

    /// 辞書 (suggestions.json) の代表キー。folder はチップを出さないので nil
    var dictionaryKey: String? {
        switch self {
        case .image:        return "photo"
        case .video:        return "video"
        case .audio:        return "music"
        case .pdf:          return "pdf"
        case .presentation: return "presentation"
        case .spreadsheet:  return "spreadsheet"
        case .code:         return "code"
        case .document:     return "document"
        case .archive:      return "zip"
        case .app:          return "app"
        case .folder:       return nil
        }
    }

    /// チップの理由「中身の多くが画像 (12 件)」。folder は nil
    func reason(count: Int) -> String? {
        switch self {
        case .image:        return String(localized: "中身の多くが画像 (\(count) 件)")
        case .video:        return String(localized: "中身の多くが動画 (\(count) 件)")
        case .audio:        return String(localized: "中身の多くが音楽 (\(count) 件)")
        case .pdf:          return String(localized: "中身の多くが PDF (\(count) 件)")
        case .presentation: return String(localized: "中身の多くがプレゼン (\(count) 件)")
        case .spreadsheet:  return String(localized: "中身の多くが表計算 (\(count) 件)")
        case .code:         return String(localized: "中身の多くがコード (\(count) 件)")
        case .document:     return String(localized: "中身の多くが書類 (\(count) 件)")
        case .archive:      return String(localized: "中身の多くが圧縮ファイル (\(count) 件)")
        case .app:          return String(localized: "中身の多くがアプリ (\(count) 件)")
        case .folder:       return nil
        }
    }

    /// UTType を列挙順で判定し、最初に当たった種類を返す。当たらなければ nil (数えない)。
    /// ソースコードは .text にも準拠するので .sourceCode を先に見る。PDF は .compositeContent にも準拠するので .pdf を先に見る
    static func classify(type: UTType?, isDirectory: Bool, isPackage: Bool) -> ContentKind? {
        if isDirectory && !isPackage { return .folder }
        guard let type else { return nil }
        if type.conforms(to: .application) { return .app }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .document }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        return nil
    }
}

/// 代表画像 (中身の多数派が画像のときの 1 枚)。等価判定は url と更新日時 (サムネイルは比較しない)
struct RepresentativeImage: Equatable, Sendable {
    let url: URL
    let modificationDate: Date
    /// 長辺 256px 以下の PNG (チップ用)
    let thumbnailPNG: Data

    static func == (a: RepresentativeImage, b: RepresentativeImage) -> Bool {
        a.url == b.url && a.modificationDate == b.modificationDate
    }
}

struct ContentSummary: Equatable, Sendable {
    let counts: [ContentKind: Int]
    /// 最多の種類。同数は ContentKind の列挙順の先。0 件なら nil
    let dominant: ContentKind?
    /// dominant == .image のときだけ
    let representative: RepresentativeImage?

    static func dominant(of counts: [ContentKind: Int]) -> ContentKind? {
        var best: (kind: ContentKind, count: Int)?
        for kind in ContentKind.allCases {
            let count = counts[kind] ?? 0
            if count > 0, count > (best?.count ?? 0) { best = (kind, count) }
        }
        return best?.kind
    }
}

/// フォルダ直下だけを逐次読んで種類を数え、画像が多数派なら代表画像のサムネイルを作る。
/// メインの外で呼ぶ (I/O)。Task の中で呼ばれたときは cancel で途中で抜ける (best effort)
enum ContentScanner {
    static let entryLimit = 1000
    static let maxImageBytes = 20 * 1024 * 1024
    /// 代表画像にする形式 (画像パネルで選べるものと同じ)
    static let representableTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff]
    /// Finder のカスタムアイコンの実体。隠し属性が付いていないことがあるので名前で除外する
    static let iconFileName = "Icon\r"

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .contentTypeKey, .contentModificationDateKey, .fileSizeKey,
    ]

    /// 読めなければ nil (フォルダごと存在しない、権限が無い、1 件も読めなかった、cancel された)。
    /// 直下の一部の項目だけが読めない (壊れたエントリなど) 場合は、その項目を飛ばして残りは数え続ける
    static func scan(_ folder: URL, limit: Int = entryLimit, maxImageBytes: Int = maxImageBytes) -> ContentSummary? {
        if Task.isCancelled { return nil }
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in failed = true; return true }
        ) else { return nil }

        var counts: [ContentKind: Int] = [:]
        var seen = 0
        var best: (url: URL, date: Date)?

        for case let url as URL in enumerator {
            if Task.isCancelled { return nil }
            if seen >= limit { break }
            seen += 1
            guard url.lastPathComponent != iconFileName,
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  let kind = ContentKind.classify(type: values.contentType,
                                                  isDirectory: values.isDirectory ?? false,
                                                  isPackage: values.isPackage ?? false) else { continue }
            counts[kind, default: 0] += 1

            guard kind == .image,
                  let type = values.contentType, representableTypes.contains(where: { type.conforms(to: $0) }),
                  (values.fileSize ?? Int.max) <= maxImageBytes,
                  let date = values.contentModificationDate else { continue }
            // 更新日時が新しいもの。同時刻は名前の昇順で先のもの
            if let current = best {
                if date > current.date || (date == current.date && url.lastPathComponent < current.url.lastPathComponent) {
                    best = (url, date)
                }
            } else {
                best = (url, date)
            }
        }
        if failed && seen == 0 { return nil }

        let dominant = ContentSummary.dominant(of: counts)
        var representative: RepresentativeImage?
        if dominant == .image, let best, let png = thumbnailPNG(of: best.url) {
            representative = RepresentativeImage(url: best.url, modificationDate: best.date, thumbnailPNG: png)
        }
        return ContentSummary(counts: counts, dominant: dominant, representative: representative)
    }

    /// 画像全体を復号せず、長辺 maxPixel 以下のサムネイルを PNG で返す。EXIF の向きを反映し、キャッシュは残さない
    static func thumbnailPNG(of url: URL, maxPixel: Int = 256) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
