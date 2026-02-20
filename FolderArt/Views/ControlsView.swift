import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {

            // 位置選択
            HStack {
                Text("画像の配置:")
                    .font(.callout)
                    .frame(width: 90, alignment: .trailing)

                Picker("", selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.radioGroup)
            }

            Divider()

            // サイズスライダー（切り抜きON時は自動フィルのため無効）
            SliderRow(
                label: "サイズ:",
                value: $settings.scale,
                range: 0.2...1.0,
                format: { "\(Int($0 * 100))%" }
            )
            .disabled(settings.clipToFolderShape)
            .opacity(settings.clipToFolderShape ? 0.4 : 1.0)

            // 不透明度スライダー
            SliderRow(
                label: "不透明度:",
                value: $settings.opacity,
                range: 0.1...1.0,
                format: { "\(Int($0 * 100))%" }
            )

            // 上下位置スライダー
            SliderRow(
                label: "上下位置:",
                value: $settings.verticalOffset,
                range: -0.4...0.4,
                format: { v in
                    if abs(v) < 0.01 { return "中央" }
                    return v > 0 ? "上\(Int(v * 100))%" : "下\(Int(-v * 100))%"
                }
            )

            Divider()

            // フルイメージ切り替え
            HStack {
                Text("")
                    .frame(width: 90, alignment: .trailing)
                Toggle("フルイメージ", isOn: $settings.clipToFolderShape)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal)
    }
}

private struct SliderRow: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label)
                .font(.callout)
                .frame(width: 90, alignment: .trailing)
            Slider(value: $value, in: range)
            Text(format(value))
                .font(.callout)
                .monospacedDigit()
                .frame(width: 44, alignment: .trailing)
        }
    }
}
