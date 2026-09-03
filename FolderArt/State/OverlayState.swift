import AppKit
import Combine

/// 4 タブの入力と、そこから作るプレビュー。
@MainActor
final class OverlayState: ObservableObject {
    enum Tab: String, CaseIterable, Identifiable {
        case image, symbol, emoji, text
        var id: String { rawValue }
    }

    @Published var activeTab: Tab = .image
    @Published var imageAssetID: UUID?
    @Published var symbolName: String?
    @Published var emoji: String = ""
    @Published var text: String = ""
    @Published var settings = CompositionSettings()

    @Published private(set) var overlayImage: NSImage?
    @Published private(set) var previewImage: NSImage?

    let assets: AssetStore
    private var cancellable: AnyCancellable?
    private var lastRenderedOverlay: Overlay?
    private var lastRenderedSettings: CompositionSettings?

    init(assets: AssetStore, debounce: TimeInterval = 0.1) {
        self.assets = assets
        // objectWillChange は変更前に飛ぶが、debounce 後には値が反映されている
        cancellable = objectWillChange
            .debounce(for: .seconds(debounce), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in self?.updatePreviewNow() }
    }

    /// 現在のタブの入力から Overlay を作る。未入力なら nil。
    var overlay: Overlay? {
        switch activeTab {
        case .image:
            return imageAssetID.map { .image(assetID: $0) }
        case .symbol:
            return symbolName.map { .symbol(name: $0) }
        case .emoji:
            let s = emoji.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : .emoji(s)
        case .text:
            let s = text.trimmingCharacters(in: .whitespacesAndNewlines)
            return s.isEmpty ? nil : .text(s)
        }
    }

    var canApply: Bool { previewImage != nil }

    /// 画像ファイルを AssetStore に複製して画像タブに切り替える
    func selectImage(url: URL) throws {
        let id = try assets.store(contentsOf: url)
        imageAssetID = id
        activeTab = .image
    }

    /// お気に入りからの復元
    func restore(overlay: Overlay, settings: CompositionSettings) {
        switch overlay {
        case .image(let id):      imageAssetID = id;  activeTab = .image
        case .symbol(let name):   symbolName = name;  activeTab = .symbol
        case .emoji(let s):       emoji = s;          activeTab = .emoji
        case .text(let s):        text = s;           activeTab = .text
        case .legacyImage:        return
        }
        self.settings = settings
        updatePreviewNow()
    }

    func updatePreviewNow() {
        let newOverlay = overlay
        if newOverlay == lastRenderedOverlay && settings == lastRenderedSettings { return }
        lastRenderedOverlay = newOverlay
        lastRenderedSettings = settings

        guard let newOverlay,
              let rendered = OverlayRenderer.render(newOverlay, settings: settings,
                                                    side: IconComposer.iconSize.width, assets: assets) else {
            overlayImage = nil
            previewImage = nil
            return
        }
        overlayImage = rendered
        previewImage = IconComposer.compose(overlay: rendered, settings: settings,
                                            fillsWhenClipped: newOverlay.fillsFolderWhenClipped)
    }
}
