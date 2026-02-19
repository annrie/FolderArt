import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    let onReset: (IconTask) -> Void

    @Environment(\.dismiss) private var dismiss

    private let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateStyle = .short
        f.timeStyle = .short
        return f
    }()

    var body: some View {
        VStack(spacing: 0) {
            // ヘッダー
            HStack {
                Text("変更履歴")
                    .font(.headline)
                Spacer()
                Button("閉じる") { dismiss() }
                    .keyboardShortcut(.cancelAction)
            }
            .padding()

            Divider()

            if historyStore.tasks.isEmpty {
                Spacer()
                Text("変更履歴はありません")
                    .foregroundColor(.secondary)
                Spacer()
            } else {
                List {
                    ForEach(historyStore.tasks) { task in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(URL(fileURLWithPath: task.folderPath).lastPathComponent)
                                    .font(.body)
                                    .lineLimit(1)
                                Text("\(task.imageName) · \(task.position.displayName)")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                Text(dateFormatter.string(from: task.appliedAt))
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("リセット") {
                                onReset(task)
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(width: 400, height: 360)
    }
}
