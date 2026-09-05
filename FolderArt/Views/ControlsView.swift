import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings
    /// 画像タブでは色は効かないので無効表示にする
    var showsTint: Bool = true
    /// フォントは文字タブでのみ効く
    var showsFont: Bool = false
    /// 太さは記号と文字で効く (画像・絵文字では無効表示)
    var showsWeight: Bool = false
    /// 切り抜き ON + 中央でサイズが効かなくなるのは画像 (敷き詰め) だけ。記号・絵文字・文字ではサイズは常に有効
    var sizeLockedByFill: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("配置:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker(selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                } label: { EmptyView() }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            SliderRow(label: "サイズ:", value: $settings.scale, range: CompositionSettings.scaleRange,
                      format: { "\(Int($0 * 100))%" })
                .disabled(sizeLockedByFill && settings.clipToFolderShape && settings.position == .center)
                .opacity(sizeLockedByFill && settings.clipToFolderShape && settings.position == .center ? 0.4 : 1.0)

            SliderRow(label: "不透明度:", value: $settings.opacity, range: CompositionSettings.opacityRange,
                      format: { "\(Int($0 * 100))%" })

            SliderRow(label: "上下位置:", value: $settings.verticalOffset, range: CompositionSettings.verticalOffsetRange,
                      format: { v in
                          if abs(v) < 0.01 { return String(localized: "中央") }
                          return v > 0 ? String(localized: "上\(Int(v * 100))%") : String(localized: "下\(Int(-v * 100))%")
                      })

            HStack {
                Text("色:").font(.callout).frame(width: 80, alignment: .trailing)
                ColorPicker(selection: tintBinding, supportsOpacity: false) {
                    EmptyView()
                }
                    .labelsHidden()
                    .disabled(!showsTint)
                    .opacity(showsTint ? 1 : 0.4)
                (showsTint ? Text("記号と文字に適用") : Text("記号と文字にのみ適用されます"))
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack {
                Text("フォント:").font(.callout).frame(width: 80, alignment: .trailing)
                // 今の値が一覧に無いとき (別の Mac のパックなど) は「その他 (名前)」を足して選択が空にならないようにする
                Picker(selection: $settings.fontName) {
                    ForEach(FontCatalog.choices(including: settings.fontName, available: FontCatalog.available())) { choice in
                        Text(choice.title).tag(choice.family)
                    }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(!showsFont)
                .opacity(showsFont ? 1 : 0.4)
            }

            HStack {
                Text("太さ:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker(selection: $settings.fontWeight) {
                    ForEach(FontWeightValue.allCases, id: \.self) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                } label: { EmptyView() }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 140)
                .disabled(!showsWeight)
                .opacity(showsWeight ? 1 : 0.4)
            }

            Divider()

            HStack {
                Text(verbatim: "").frame(width: 80, alignment: .trailing)
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
