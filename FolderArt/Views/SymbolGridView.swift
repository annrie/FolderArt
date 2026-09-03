import SwiftUI

/// 記号タブの中身: 検索欄 + グリッド。
struct SymbolGridView: View {
    let catalog: SymbolCatalog
    @Binding var selected: String?

    @State private var query = ""
    @State private var results: [String] = []
    private let columns = Array(repeating: GridItem(.fixed(34), spacing: 4), count: 8)

    var body: some View {
        VStack(spacing: 6) {
            TextField("検索 (folder, star, camera…)", text: $query)
                .textFieldStyle(.roundedBorder)
            ScrollView {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(results, id: \.self) { name in
                        Button { selected = name } label: {
                            Image(systemName: name)
                                .font(.system(size: 16))
                                .frame(width: 34, height: 34)
                                .background(
                                    RoundedRectangle(cornerRadius: 6)
                                        .fill(selected == name ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.08))
                                )
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .strokeBorder(selected == name ? Color.accentColor : .clear, lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(.plain)
                        .help(Text(name))
                    }
                }
                .padding(2)
            }
            if let selected {
                Text(selected).font(.caption).foregroundColor(.secondary).lineLimit(1)
            }
        }
        .onAppear { results = catalog.search(query) }
        .onChange(of: query) { results = catalog.search($0) }
    }
}
