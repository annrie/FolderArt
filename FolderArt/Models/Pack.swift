import Foundation

/// パックの 1 項目。id と createdAt は持たない (受け取り側で振り直す)。
struct PackEntry: Codable, Equatable {
    var name: String
    var overlay: Overlay
    var settings: CompositionSettings
    /// overlay が .image のときだけ PNG (Base64 で JSON に入る)
    var image: Data?
}

struct Pack: Codable, Equatable {
    static let currentFormat = 1
    var format: Int
    var app: String
    var appVersion: String
    var exportedAt: Date
    var presets: [PackEntry]
}

enum PackError: LocalizedError, Equatable {
    case unsupportedFormat(Int)
    case corrupted
    case tooManyPresets(Int)
    case missingImage(String)
    case invalidImage(String)
    case invalidSettings(String)
    case fileTooLarge
    case imageTooLarge(String)
    case assetUnavailable(String)
    case symbolUnavailable(String, String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat:
            return String(localized: "このパックは新しいバージョンの FolderArt で作られています。")
        case .corrupted:
            return String(localized: "パックを読み込めません (ファイルが壊れています)。")
        case .tooManyPresets(let n):
            return String(localized: "パックの項目が多すぎます (\(n) 件、上限 \(PackWriter.maxPresets) 件)。")
        case .missingImage(let name):
            return String(localized: "「\(name)」の画像がパックに含まれていません。")
        case .invalidImage(let name):
            return String(localized: "「\(name)」の画像を読み込めません。")
        case .invalidSettings(let name):
            return String(localized: "「\(name)」の設定が範囲外です。")
        case .fileTooLarge:
            return String(localized: "パックが大きすぎます (上限 \(PackReader.maxFileBytes / 1024 / 1024) MB)。")
        case .imageTooLarge(let name):
            return String(localized: "「\(name)」の画像が大きすぎます (上限 \(PackReader.maxImageBytes / 1024 / 1024) MB)。")
        case .assetUnavailable(let name):
            return String(localized: "「\(name)」の画像が見つからないため書き出せません。")
        case .symbolUnavailable(let name, let symbol):
            return String(localized: "「\(name)」の記号「\(symbol)」はこの macOS にありません。")
        }
    }
}

struct ImportSummary: Equatable {
    var added: Int
    var skippedIdentical: Int
}
