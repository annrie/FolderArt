import SwiftUI

/// 適用先フォルダのリスト。全体がドロップ先。行は複数選択可 (選択があればその分だけに適用)。
struct FolderListView: View {
    @ObservedObject var selection: FolderSelection
    let onAdd: () -> Void
    /// フォルダ・画像を問わず全件をそのまま渡す (振り分けは AppModel が行う)
    let onDrop: ([URL]) -> Void

    @State private var isTargeted = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("フォルダー (\(selection.folders.count))")
                    .font(.callout).foregroundColor(.secondary)
                Spacer()
                if !selection.selectedIDs.isEmpty {
                    Button("選択解除") { selection.clearSelection() }
                        .buttonStyle(.borderless).font(.caption)
                }
                Button { onAdd() } label: { Image(systemName: "plus") }
                    .buttonStyle(.borderless)
                    .help(Text("フォルダーを追加…"))
            }

            if selection.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32))
                        .foregroundColor(isTargeted ? .accentColor : .secondary)
                    Text("フォルダーをここにドロップ")
                        .font(.callout).foregroundColor(.secondary)
                    Button("フォルダーを選択…", action: onAdd).buttonStyle(.borderless)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(selection.folders, id: \.self, selection: $selection.selectedIDs) { url in
                    HStack(spacing: 6) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                            .resizable().frame(width: 16, height: 16)
                        Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                        Spacer()
                        Button { selection.remove(url) } label: { Image(systemName: "xmark.circle.fill") }
                            .buttonStyle(.borderless).foregroundColor(.secondary)
                            .help(Text("リストから外す"))
                    }
                    .help(Text(url.path))
                }
                .listStyle(.inset)
                .onExitCommand { selection.clearSelection() }
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                              style: StrokeStyle(lineWidth: 2, dash: [6]))
        )
        .background(RoundedRectangle(cornerRadius: 12).fill(isTargeted ? Color.accentColor.opacity(0.05) : .clear))
        .overlay(
            FileDropReceiver(
                isTargeted: $isTargeted,
                // 画像を落とされても弾かない。AppKit は下のビューへ落とし直してくれないので、
                // ここで受けて AppModel に振り分けさせる
                accepts: { $0.contains { DropZoneView.isDirectory($0) || DropZoneView.isImage($0) } },
                onDrop: { onDrop($0) }
            )
        )
    }
}
