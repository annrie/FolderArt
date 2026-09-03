import AppKit

/// JSON に保存できる sRGB 色。
struct CodableColor: Codable, Equatable, Sendable {
    var red: Double
    var green: Double
    var blue: Double
    var alpha: Double

    static let white = CodableColor(red: 1, green: 1, blue: 1, alpha: 1)
    static let black = CodableColor(red: 0, green: 0, blue: 0, alpha: 1)

    init(red: Double, green: Double, blue: Double, alpha: Double) {
        self.red = red; self.green = green; self.blue = blue; self.alpha = alpha
    }

    init(_ color: NSColor) {
        let c = color.usingColorSpace(.sRGB) ?? color
        self.init(red: Double(c.redComponent), green: Double(c.greenComponent),
                  blue: Double(c.blueComponent), alpha: Double(c.alphaComponent))
    }

    var nsColor: NSColor {
        NSColor(srgbRed: red, green: green, blue: blue, alpha: alpha)
    }
}

/// 文字系オーバーレイの太さ。第1段階では UI に出さず初期値 (.bold) のみ使う。
enum FontWeightValue: String, Codable, CaseIterable, Sendable {
    case regular, medium, semibold, bold, heavy, black

    var nsWeight: NSFont.Weight {
        switch self {
        case .regular:  return .regular
        case .medium:   return .medium
        case .semibold: return .semibold
        case .bold:     return .bold
        case .heavy:    return .heavy
        case .black:    return .black
        }
    }
}
