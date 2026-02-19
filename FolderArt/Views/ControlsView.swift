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

            // サイズスライダー
            SliderRow(
                label: "サイズ:",
                value: $settings.scale,
                range: 0.2...1.0,
                format: { "\(Int($0 * 100))%" }
            )

            // 不透明度スライダー
            SliderRow(
                label: "不透明度:",
                value: $settings.opacity,
                range: 0.1...1.0,
                format: { "\(Int($0 * 100))%" }
            )
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
