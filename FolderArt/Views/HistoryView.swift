import SwiftUI

struct HistoryView: View {
    @ObservedObject var historyStore: HistoryStore
    let onReset: (IconTask) -> Void
    let onReapply: (IconTask) -> Void
    var isApplying: Bool = false

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
                                    .font(.body).lineLimit(1)
                                HStack(spacing: 4) {
                                    Text("\(task.overlay.displayName) · \(task.settings.position.displayName)")
                                    if !task.overlay.canReapply {
                                        Text("(旧形式)").foregroundColor(.orange)
                                    }
                                    if task.bookmarkData.isEmpty {
                                        Text("(ここからのリセット不可)").foregroundColor(.orange)
                                    }
                                }
                                .font(.caption).foregroundColor(.secondary)
                                Text(dateFormatter.string(from: task.appliedAt))
                                    .font(.caption2).foregroundColor(.secondary)
                            }
                            Spacer()
                            Button("再適用") { onReapply(task) }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(!task.overlay.canReapply || isApplying)
                                .help(Text("この見た目とフォルダーを画面に戻す"))
                            Button("リセット") { onReset(task) }
                                .buttonStyle(.bordered).controlSize(.small)
                                .disabled(task.bookmarkData.isEmpty || isApplying)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .frame(minWidth: 480, minHeight: 360)
    }
}
