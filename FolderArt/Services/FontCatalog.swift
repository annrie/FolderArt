import AppKit
import SwiftUI

/// 文字のフォントの選択肢 1 つ。family が nil ならシステム丸ゴシック (CompositionSettings.fontName の nil と同じ意味)
struct FontChoice: Identifiable {
    let family: String?
    let title: LocalizedStringKey
    var id: String { family ?? "" }
}

/// macOS 同梱の厳選フォントと、家族名 + 太さから NSFont を作る解決規則。
/// fontName にはファミリ名を入れる (PostScript 名ではない)。別の Mac に無い家族は既定に落ちる。
enum FontCatalog {

    /// この順に Picker へ出す。どの Mac にもあるものだけ (macOS 13 の標準構成で確認)
    static let choices: [FontChoice] = [
        FontChoice(family: nil, title: "丸ゴシック (システム)"),
        FontChoice(family: "Hiragino Sans", title: "ヒラギノ角ゴシック"),
        FontChoice(family: "Hiragino Mincho ProN", title: "ヒラギノ明朝"),
        FontChoice(family: "Hiragino Maru Gothic ProN", title: "ヒラギノ丸ゴ"),
        FontChoice(family: "Tsukushi A Round Gothic", title: "筑紫A丸ゴシック"),
        FontChoice(family: "Klee", title: "クレー"),
        FontChoice(family: "Avenir Next", title: "Avenir Next"),
        FontChoice(family: "Menlo", title: "Menlo (等幅)"),
    ]

    /// この Mac にある家族名。起動後 1 回だけ取得 (描画のたびに NSFontManager を引かない。起動後に入れたフォントは次回起動から)
    static let installedFamilies: Set<String> = Set(NSFontManager.shared.availableFontFamilies)

    /// この Mac にあるものだけ。先頭 (nil = 丸ゴシック) は常に含む
    static func available(families: Set<String> = installedFamilies) -> [FontChoice] {
        choices.filter { choice in choice.family.map { families.contains($0) } ?? true }
    }

    /// Picker 用: 今の値が一覧に無ければ「その他 (名前)」を末尾に足す (SwiftUI の Picker は選択値が一覧に無いと空表示になる)。
    /// 設定の値は書き換えない。選び直せばこの項目は消える
    static func choices(including current: String?, available: [FontChoice]) -> [FontChoice] {
        guard let current, !available.contains(where: { $0.family == current }) else { return available }
        return available + [FontChoice(family: current, title: "その他 (\(current))")]
    }

    /// 解決順: nil → 丸ゴシック / 家族がある → 家族 + 太さの descriptor (無い太さは一番近い顔) /
    /// 家族が無い → NSFont(name:) (PostScript 名の互換) / どれも無い → 丸ゴシック
    static func font(family: String?, weight: FontWeightValue, size: CGFloat,
                     families: Set<String> = installedFamilies) -> NSFont {
        if let family {
            if families.contains(family) {
                let descriptor = NSFontDescriptor(fontAttributes: [
                    .family: family,
                    .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight.rawValue],
                ])
                // 家族が無いと別の家族に置き換わることがあるので、返った家族名を確かめる
                if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family {
                    return font
                }
            }
            if let named = NSFont(name: family, size: size) {
                return named
            }
        }
        return systemRounded(weight: weight, size: size)
    }

    /// システムフォントの rounded デザイン (1.3.0 までの既定と同じ)
    static func systemRounded(weight: FontWeightValue, size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        if let rounded = system.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: size) {
            return font
        }
        return system
    }
}
