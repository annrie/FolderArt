import AppKit
import SwiftUI

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

    /// 各成分が有限で 0...1 に収まっていること (NaN は contains が false を返す)
    var isValid: Bool {
        [red, green, blue, alpha].allSatisfy { (0.0...1.0).contains($0) }
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

extension FontWeightValue {
    /// Picker の表示名 (太さの UI は第3段階で開放)
    var displayName: LocalizedStringKey {
        switch self {
        case .regular:  return "標準"
        case .medium:   return "中太"
        case .semibold: return "半太"
        case .bold:     return "太字"
        case .heavy:    return "特太"
        case .black:    return "極太"
        }
    }
}
