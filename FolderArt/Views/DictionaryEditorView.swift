import SwiftUI

/// 提案辞書の編集ウィンドウの中身。左に項目一覧、右に選択項目の詳細 (キー / 記号 / 絵文字)、下に保存バー。
struct DictionaryEditorView: View {
    @StateObject private var model: DictionaryEditorModel
    @Environment(\.dismiss) private var dismiss

    /// 詳細ペインの「キーを追加」欄。選択が変わったら空に戻す
    @State private var newKeyText = ""
    /// 選択切替時に「打ちかけのキー」を元の行へ取りこぼさず反映するため、直前の選択を覚える
    @State private var lastSelection: DictionaryEditorModel.Row.ID?

    init(url: URL, catalog: SymbolCatalog = .shared) {
        _model = StateObject(wrappedValue: DictionaryEditorModel(url: url, catalog: catalog))
    }

    private var selectedRow: DictionaryEditorModel.Row? {
        guard let id = model.selection else { return nil }
        return model.rows.first { $0.id == id }
    }

    var body: some View {
        HSplitView {
            listPane.frame(minWidth: 220)
            detailPane.frame(minWidth: 380)
        }
        .frame(minWidth: 680, minHeight: 460)
        .safeAreaInset(edge: .bottom) { saveBar }
        .onAppear { model.reload(); lastSelection = model.selection }               // 開くたびに最新化
        .onChange(of: model.selection) { newSelection in
            // 選択を切り替える前の行に、打ちかけのキーを取りこぼさず反映してからクリアする
            if let previous = lastSelection,
               !newKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                model.addKey(newKeyText, to: previous)
            }
            newKeyText = ""
            lastSelection = newSelection
        }
        .alert("お知らせ", isPresented: Binding(get: { model.errorMessage != nil },
                                            set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK") { model.errorMessage = nil }
        } message: { Text(model.errorMessage ?? "") }
        .alert("ファイルが変更されています。上書きしますか？ 読み直しますか？", isPresented: $model.pendingExternalChange) {
            Button("上書き") { model.save(force: true) }
            Button("読み直す", role: .cancel) { model.reload() }
        }
        .alert("このファイルは読み込めません。上書きすると元の内容は失われます。上書きしますか？",
               isPresented: $model.pendingOverwriteUnreadable) {
            Button("上書きする", role: .destructive) { model.save(force: true) }
            Button("やめる", role: .cancel) { }
        }
    }

    // MARK: - 左: 項目一覧

    private var listPane: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("提案辞書の編集").font(.headline)
                Spacer()
                Button { model.addRow() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(Text("項目を追加"))
                Button { deleteSelectedRow() } label: { Image(systemName: "minus") }
                    .buttonStyle(.borderless)
                    .disabled(model.selection == nil)
                    .help(Text("項目を削除"))
            }
            List(selection: $model.selection) {
                ForEach(model.rows) { row in
                    HStack(spacing: 6) {
                        rowIcon(row)
                        Text(row.keys.isEmpty ? String(localized: "(キー未設定)") : row.keys.joined(separator: ", "))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }
            }
            .listStyle(.inset)
        }
        .padding(8)
    }

    @ViewBuilder
    private func rowIcon(_ row: DictionaryEditorModel.Row) -> some View {
        if let symbol = row.symbol {
            Image(systemName: symbol).frame(width: 18)
        } else if let emoji = row.emoji {
            Text(emoji).frame(width: 18)
        } else {
            Image(systemName: "questionmark.circle").foregroundColor(.secondary).frame(width: 18)
        }
    }

    private func deleteSelectedRow() {
        guard let id = model.selection else { return }
        model.deleteRows([id])
    }

    /// 「キーを追加」欄に打ちかけのテキストがあれば、保存前に選択行へ反映する。
    /// (Return を押さずに保存した時にキーが失われるのを防ぐ)
    private func commitPendingKeyThenSave() {
        if let id = model.selection,
           !newKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            model.addKey(newKeyText, to: id)
            newKeyText = ""
        }
        model.save()
    }

    // MARK: - 右: 選択項目の詳細

    @ViewBuilder
    private var detailPane: some View {
        if let row = selectedRow {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    keysSection(row)
                    symbolSection(row)
                    emojiSection(row)
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack {
                Spacer()
                Text("左で項目を選ぶか＋で追加してください")
                    .foregroundColor(.secondary)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func keysSection(_ row: DictionaryEditorModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("キー").font(.callout).foregroundColor(.secondary)
            if !row.keys.isEmpty {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 80), spacing: 6)], alignment: .leading, spacing: 6) {
                    ForEach(row.keys, id: \.self) { key in
                        HStack(spacing: 4) {
                            Text(key).lineLimit(1).truncationMode(.middle)
                            Button { model.removeKey(key, from: row.id) } label: {
                                Image(systemName: "xmark.circle.fill")
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(.secondary)
                        }
                        .font(.callout)
                        .padding(.horizontal, 8).padding(.vertical, 4)
                        .background(Capsule().fill(Color.secondary.opacity(0.12)))
                    }
                }
            }
            TextField("キーを追加", text: $newKeyText)
                .textFieldStyle(.roundedBorder)
                .frame(maxWidth: 240)
                .onSubmit {
                    model.addKey(newKeyText, to: row.id)
                    newKeyText = ""
                }
        }
    }

    private func symbolSection(_ row: DictionaryEditorModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("記号").font(.callout).foregroundColor(.secondary)
                Spacer()
                if row.symbol != nil {
                    Button("記号をクリア") { model.setSymbol(nil, for: row.id) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            SymbolGridView(catalog: model.catalog, selected: symbolBinding(row))
                .frame(height: 200)
        }
    }

    private func symbolBinding(_ row: DictionaryEditorModel.Row) -> Binding<String?> {
        Binding(
            get: { row.symbol },
            set: { model.setSymbol($0, for: row.id) }
        )
    }

    private func emojiSection(_ row: DictionaryEditorModel.Row) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("絵文字").font(.callout).foregroundColor(.secondary)
                Spacer()
                if row.emoji != nil {
                    Button("クリア") { model.setEmoji(nil, for: row.id) }
                        .buttonStyle(.borderless).font(.caption)
                }
            }
            TextField("絵文字を入力", text: emojiBinding(row))
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 20))
                .frame(maxWidth: 120)
        }
    }

    private func emojiBinding(_ row: DictionaryEditorModel.Row) -> Binding<String> {
        Binding(
            get: { row.emoji ?? "" },
            set: { newValue in
                // OverlayPickerView の絵文字欄と同様、1 文字 (1 書記素) に制限
                model.setEmoji(newValue.count > 1 ? String(newValue.suffix(1)) : newValue, for: row.id)
            }
        )
    }

    // MARK: - 下: 保存バー

    private var saveBar: some View {
        HStack {
            Spacer()
            Button("保存") { commitPendingKeyThenSave() }
                .keyboardShortcut(.defaultAction)
                .disabled(!model.isDirty && newKeyText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            Button("閉じる") { dismiss() }
        }
        .padding(8)
        .background(.bar)
    }
}
