import Foundation

struct CompositionSettings: Codable, Equatable, Sendable {
    var position: IconPosition = .center
    var scale: Double = 0.6              // 0.2 ... 1.0
    var opacity: Double = 0.9            // 0.1 ... 1.0
    /// 上下位置 (−0.4 … 0.4、上が正)。既定は「下4%」: 標準フォルダアイコンは蓋の分だけ本体が下に寄っているので、
    /// 正方形の中央に置くと少し上に見える。本体 (蓋を除く) の中心は macOS 15.7 の実測で正方形の中央より 4.0% 下
    /// (IconComposer.folderBodyCenterOffset(of:) を参照。IconComposerTests の見張りテストが OS の変化を知らせる)。
    /// 保存済みの設定は自分の値を持つので変わらない
    var verticalOffset: Double = -0.04   // -0.4 ... 0.4 (上:正, 下:負)
    var clipToFolderShape: Bool = true   // フォルダー形状に切り抜く
    var tintColor: CodableColor = .white // 記号・文字の色
    var fontName: String? = nil          // nil = システムフォント (rounded)。第3段階で UI 開放
    var fontWeight: FontWeightValue = .bold
}

extension CompositionSettings {
    /// UI のスライダーと同じ範囲。パックなど外から来た値の検証にも使う (範囲の定義はここだけ)
    static let scaleRange: ClosedRange<Double> = 0.2...1.0
    static let opacityRange: ClosedRange<Double> = 0.1...1.0
    static let verticalOffsetRange: ClosedRange<Double> = -0.4...0.4

    /// 全ての数値が有限で範囲内、色成分が 0...1、fontName が空文字でないこと
    var isValid: Bool {
        Self.scaleRange.contains(scale)
            && Self.opacityRange.contains(opacity)
            && Self.verticalOffsetRange.contains(verticalOffset)
            && tintColor.isValid
            && (fontName.map { !$0.isEmpty } ?? true)
    }
}

// memberwise init を残すため、カスタムデコードは extension に置く
extension CompositionSettings {
    private enum CodingKeys: String, CodingKey {
        case position, scale, opacity, verticalOffset, clipToFolderShape, tintColor, fontName, fontWeight
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = CompositionSettings()
        position          = try c.decodeIfPresent(IconPosition.self,    forKey: .position)          ?? d.position
        scale             = try c.decodeIfPresent(Double.self,          forKey: .scale)             ?? d.scale
        opacity           = try c.decodeIfPresent(Double.self,          forKey: .opacity)           ?? d.opacity
        verticalOffset    = try c.decodeIfPresent(Double.self,          forKey: .verticalOffset)    ?? d.verticalOffset
        clipToFolderShape = try c.decodeIfPresent(Bool.self,            forKey: .clipToFolderShape) ?? d.clipToFolderShape
        tintColor         = try c.decodeIfPresent(CodableColor.self,    forKey: .tintColor)         ?? d.tintColor
        fontName          = try c.decodeIfPresent(String.self,          forKey: .fontName)
        fontWeight        = try c.decodeIfPresent(FontWeightValue.self, forKey: .fontWeight)        ?? d.fontWeight
    }
}
