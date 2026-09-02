import AppKit
import Combine
import SwiftUI
import UniformTypeIdentifiers

/// 画面全体の状態を束ねる。個別の責務は FolderSelection / OverlayState / ApplyCoordinator が持つ。
@MainActor
final class AppModel: ObservableObject {
    let folders: FolderSelection
    let overlay: OverlayState
    let history: HistoryStore
    let presets: PresetStore
    let assets: AssetStore
    private let coordinator: ApplyCoordinator

    @Published var errorMessage: String?
    @Published var isApplying = false
    @Published var progress: (done: Int, total: Int)?
    private var cancellables: Set<AnyCancellable> = []

    init(history: HistoryStore = HistoryStore(),
         presets: PresetStore = PresetStore(),
         assets: AssetStore = AssetStore()) {
        self.history = history
        self.presets = presets
        self.assets = assets
        self.folders = FolderSelection()
        self.overlay = OverlayState(assets: assets)
        self.coordinator = ApplyCoordinator(history: history)

        // 子オブジェクトの変更を自分の変更として流し、ContentView を再描画させる
        for child in [folders.objectWillChange.eraseToAnyPublisher(),
                      overlay.objectWillChange.eraseToAnyPublisher(),
                      history.objectWillChange.eraseToAnyPublisher(),
                      presets.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }

        if let e = history.loadError ?? presets.loadError {
            errorMessage = String(localized: "保存データの読み込みに失敗しました: \(e.localizedDescription)")
        }
        reapAssets()
    }

    // MARK: - 適用

    var canApply: Bool { !folders.isEmpty && overlay.canApply && !isApplying }

    var applyButtonTitle: String {
        let n = folders.targets.count
        if isApplying { return String(localized: "適用中…") }
        return folders.selectedIDs.isEmpty
            ? String(localized: "\(n) フォルダに適用")
            : String(localized: "選択した \(n) フォルダに適用")
    }

    func apply() async {
        // デバウンス待ちで overlayImage が古いままだと、適用と履歴で違うオーバーレイになりうる。
        // 同期描画済みなら updatePreviewNow() は何もしない (lastRendered* ガードで冪等)。
        overlay.updatePreviewNow()
        guard let overlayValue = overlay.overlay, let image = overlay.overlayImage else { return }
        let targets = folders.targets
        guard !targets.isEmpty else { return }
        isApplying = true
        progress = (0, targets.count)
        defer { isApplying = false; progress = nil }

        let outcome = await coordinator.apply(
            overlayImage: image, overlay: overlayValue, settings: overlay.settings,
            to: targets, progress: { [weak self] done, total in self?.progress = (done, total) })
        // 全件成功なら静かに終わる (既に出ているアラートを消さない)
        if let summary = outcome.summary { errorMessage = summary }
        reapAssets()
    }

    // MARK: - リセット

    /// 適用先のうち FolderArt が適用した (履歴に行がある) フォルダが 1 つでもあれば戻せる
    var canReset: Bool {
        !isApplying && folders.targets.contains { hasHistory($0) }
    }

    /// 適用先 (選択 or 全部) のうち、FolderArt が適用したフォルダだけアイコンを戻す
    func resetTargets() {
        for url in folders.targets where hasHistory(url) {
            do { try coordinator.reset(folder: url) }
            catch { errorMessage = error.localizedDescription }
        }
        reapAssets()
    }

    private func hasHistory(_ url: URL) -> Bool {
        history.task(forFolderPath: url.standardizedFileURL.path) != nil
    }

    func reset(task: IconTask) {
        do { try coordinator.reset(task) }
        catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    // MARK: - フォルダと画像の入力

    func addFolders(_ urls: [URL]) { folders.add(urls) }

    func selectFoldersWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "追加")
        if panel.runModal() == .OK { folders.add(panel.urls) }
    }

    func selectImageWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP, .tiff]
        panel.prompt = String(localized: "画像を選択")
        if panel.runModal() == .OK, let url = panel.url { selectImage(url) }
    }

    func selectImage(_ url: URL) {
        do { try overlay.selectImage(url: url) }
        catch { errorMessage = error.localizedDescription }
    }

    /// ドロップされた URL をフォルダと画像に振り分ける。画像は最初の 1 枚だけ使う。
    func handleDroppedURLs(_ urls: [URL]) {
        var dirs: [URL] = []
        var firstImage: URL?
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                dirs.append(url)
            } else if firstImage == nil, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                firstImage = url
            }
        }
        if !dirs.isEmpty { folders.add(dirs) }
        if let image = firstImage { selectImage(image) }
    }

    // MARK: - お気に入り

    func saveCurrentAsPreset() {
        guard let o = overlay.overlay else { return }
        do { try presets.add(name: nil, overlay: o, settings: overlay.settings) }
        catch { errorMessage = error.localizedDescription }
    }

    func applyPreset(_ preset: Preset) {
        overlay.restore(overlay: preset.overlay, settings: preset.settings)
    }

    /// 履歴の行を現在の入力に戻す (旧形式は不可)。フォルダがまだあればリストに足す。
    func restore(from task: IconTask) {
        guard task.overlay.canReapply else { return }
        overlay.restore(overlay: task.overlay, settings: task.settings)
        folders.add([folderURL(for: task)])
    }

    /// 履歴の行が指すフォルダ。App Sandbox 下では再起動後に素のパスでは書き込めないので、
    /// ブックマークがあればそちらを優先する。
    private func folderURL(for task: IconTask) -> URL {
        guard !task.bookmarkData.isEmpty,
              let url = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            return URL(fileURLWithPath: task.folderPath)
        }
        // リストに残っている間ずっとアクセス権が要る。このセッションの間は開いたままにする
        // (アプリ終了時に OS がまとめて解放する)
        _ = url.startAccessingSecurityScopedResource()
        return url
    }

    func removePreset(_ preset: Preset) {
        do { try presets.remove(preset) } catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    func renamePreset(_ preset: Preset, to name: String) {
        do { try presets.rename(preset, to: name) } catch { errorMessage = error.localizedDescription }
    }

    // MARK: - 画像の回収

    /// 履歴・お気に入り・現在の選択のどれからも参照されない PNG を消す。
    /// どちらかのストアが読めていない (空で始まっている) ときは、参照中の画像を消さないよう何もしない。
    func reapAssets() {
        guard history.loadError == nil, presets.loadError == nil else { return }
        var keep = history.referencedAssetIDs.union(presets.referencedAssetIDs)
        if let id = overlay.imageAssetID { keep.insert(id) }
        _ = try? assets.reap(keeping: keep)
    }
}
