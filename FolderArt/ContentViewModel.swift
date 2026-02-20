import AppKit
import SwiftUI
import Combine

@MainActor
class ContentViewModel: ObservableObject {
    // MARK: - 入力
    @Published var selectedFolderURL: URL?   { didSet { updatePreview() } }
    @Published var selectedImage: NSImage?   { didSet { updatePreview() } }
    @Published var imageName: String = ""

    // MARK: - 設定
    @Published var settings = CompositionSettings() { didSet { updatePreview() } }

    // MARK: - 出力
    @Published var previewImage: NSImage?
    @Published var errorMessage: String?
    @Published var isApplying: Bool = false

    // MARK: - 依存サービス
    let historyStore: HistoryStore
    private let iconManager = FolderIconManager()

    init(historyStore: HistoryStore = HistoryStore()) {
        self.historyStore = historyStore
    }

    var canApply: Bool {
        selectedFolderURL != nil && selectedImage != nil
    }

    // MARK: - プレビュー更新

    func updatePreview() {
        guard let folderURL = selectedFolderURL,
              let image = selectedImage else {
            previewImage = nil
            return
        }
        previewImage = IconComposer.compose(
            folderPath: folderURL.path,
            customImage: image,
            settings: settings
        )
    }

    // MARK: - アイコン適用

    func applyIcon() async {
        guard let folderURL = selectedFolderURL,
              let image = selectedImage,
              let composedImage = previewImage else { return }

        isApplying = true
        defer { isApplying = false }

        do {
            // バックアップ
            let backupURL = try iconManager.backupCurrentIcon(for: folderURL)

            // Security-Scoped Bookmark 作成
            let bookmarkData = try BookmarkManager.createBookmark(for: folderURL)

            // アイコン適用
            let success = iconManager.applyIcon(composedImage, to: folderURL)
            guard success else {
                errorMessage = "アイコンの適用に失敗しました。フォルダーへの書き込み権限を確認してください。"
                return
            }

            // 履歴に追加
            let task = IconTask(
                folderPath: folderURL.path,
                bookmarkData: bookmarkData,
                backupPath: backupURL?.path ?? "",
                imageName: imageName.isEmpty ? "カスタム画像" : imageName,
                position: settings.position,
                scale: settings.scale,
                opacity: settings.opacity,
                verticalOffset: settings.verticalOffset,
                clipToFolderShape: settings.clipToFolderShape
            )
            historyStore.add(task)
            errorMessage = nil

        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - アイコンリセット

    /// 現在選択中のフォルダーをリセット（同一セッション用: URL を直接使用）
    func resetCurrentIcon() {
        guard let folderURL = selectedFolderURL else { return }

        let task = historyStore.tasks.first(where: { $0.folderPath == folderURL.path })
        let backupURL = task.flatMap {
            $0.backupPath.isEmpty ? nil : URL(fileURLWithPath: $0.backupPath)
        }
        iconManager.resetIcon(for: folderURL, backupURL: backupURL)
        if let task { historyStore.remove(task) }
        updatePreview()
    }

    /// 履歴からのリセット（別セッション再開用: ブックマーク経由）
    func resetIcon(task: IconTask) {
        guard let resolvedURL = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            errorMessage = "フォルダーへのアクセスが無効になっています。"
            return
        }

        let backupURL = task.backupPath.isEmpty ? nil : URL(fileURLWithPath: task.backupPath)
        _ = resolvedURL.startAccessingSecurityScopedResource()
        defer { resolvedURL.stopAccessingSecurityScopedResource() }

        iconManager.resetIcon(for: resolvedURL, backupURL: backupURL)
        historyStore.remove(task)
    }

    // MARK: - フォルダー選択

    func selectFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "フォルダーを選択"

        if panel.runModal() == .OK, let url = panel.url {
            selectedFolderURL = url
        }
    }

    // MARK: - 画像選択

    func selectImage() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP]
        panel.prompt = "画像を選択"

        if panel.runModal() == .OK, let url = panel.url,
           let image = NSImage(contentsOf: url) {
            selectedImage = image
            imageName = url.lastPathComponent
        }
    }
}
