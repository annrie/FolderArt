import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings
    /// 画像タブでは色は効かないので無効表示にする
    var showsTint: Bool = true

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("配置:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker("", selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            SliderRow(label: "サイズ:", value: $settings.scale, range: 0.2...1.0,
                      format: { "\(Int($0 * 100))%" })
                .disabled(settings.clipToFolderShape && settings.position == .center)
                .opacity(settings.clipToFolderShape && settings.position == .center ? 0.4 : 1.0)

            SliderRow(label: "不透明度:", value: $settings.opacity, range: 0.1...1.0,
                      format: { "\(Int($0 * 100))%" })

            SliderRow(label: "上下位置:", value: $settings.verticalOffset, range: -0.4...0.4,
                      format: { v in
                          if abs(v) < 0.01 { return String(localized: "中央") }
                          return v > 0 ? String(localized: "上\(Int(v * 100))%") : String(localized: "下\(Int(-v * 100))%")
                      })

            HStack {
                Text("色:").font(.callout).frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: tintBinding, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!showsTint)
                    .opacity(showsTint ? 1 : 0.4)
                Text(showsTint ? "記号と文字に適用" : "記号と文字にのみ適用されます")
                    .font(.caption).foregroundColor(.secondary)
            }

            Divider()

            HStack {
                Text("").frame(width: 80, alignment: .trailing)
                // 表示名を内部名 (clipToFolderShape) と一致させる
                Toggle("フォルダー形に切り抜く", isOn: $settings.clipToFolderShape)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal)
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.tintColor.nsColor) },
            set: { settings.tintColor = CodableColor(NSColor($0)) }
        )
    }
}

private struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label).font(.callout).frame(width: 80, alignment: .trailing)
            Slider(value: $value, in: range)
            Text(format(value)).font(.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}
