import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DropZoneView: View {
    enum Mode {
        case folder
        case image
    }

    let mode: Mode
    let onDropURL: (URL) -> Void
    let onTapButton: () -> Void

    @State private var isTargeted = false
    private let displayURL: URL?
    private let previewImage: NSImage?

    init(
        mode: Mode,
        selectedURL: URL?,
        previewImage: NSImage?,
        onDropURL: @escaping (URL) -> Void,
        onTapButton: @escaping () -> Void
    ) {
        self.mode = mode
        self.displayURL = selectedURL
        self.previewImage = previewImage
        self.onDropURL = onDropURL
        self.onTapButton = onTapButton
    }

    private var placeholderIcon: String {
        switch mode {
        case .folder: return "folder.fill"
        case .image:  return "photo.fill"
        }
    }

    private var dropLabel: String {
        switch mode {
        case .folder: return "フォルダーをここにドロップ"
        case .image:  return "画像をここにドロップ"
        }
    }

    private var buttonLabel: String {
        switch mode {
        case .folder: return displayURL == nil ? "フォルダーを選択..." : "変更..."
        case .image:  return displayURL == nil ? "画像を選択..."     : "変更..."
        }
    }

    var body: some View {
        VStack(spacing: 8) {
            if let img = previewImage {
                Image(nsImage: img)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 72, height: 72)
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .shadow(radius: 2)
            } else {
                Image(systemName: placeholderIcon)
                    .font(.system(size: 36))
                    .foregroundColor(isTargeted ? .accentColor : .secondary)

                Text(dropLabel)
                    .font(.callout)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
            }

            Button(buttonLabel, action: onTapButton)
                .buttonStyle(.borderless)

            if let url = displayURL {
                Text(url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .padding(.horizontal, 8)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 140)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(
                    isTargeted ? Color.accentColor : Color.secondary.opacity(0.3),
                    style: StrokeStyle(lineWidth: 2, dash: [6])
                )
        )
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isTargeted ? Color.accentColor.opacity(0.05) : Color.clear)
        )
        // SwiftUI の onDrop は macOS で信頼性が低いため AppKit overlay で処理
        .overlay(
            AppKitDropReceiver(mode: mode, isTargeted: $isTargeted, onDropURL: onDropURL)
        )
        .padding(4)
    }
}

// MARK: - AppKit D&D レシーバー

private struct AppKitDropReceiver: NSViewRepresentable {
    let mode: DropZoneView.Mode
    @Binding var isTargeted: Bool
    let onDropURL: (URL) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> DropReceiverNSView {
        let view = DropReceiverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropReceiverNSView, context: Context) {
        context.coordinator.parent = self
    }

    // MARK: Coordinator

    class Coordinator {
        var parent: AppKitDropReceiver

        init(_ parent: AppKitDropReceiver) {
            self.parent = parent
        }

        var mode: DropZoneView.Mode { parent.mode }

        func setTargeted(_ value: Bool) {
            DispatchQueue.main.async { self.parent.isTargeted = value }
        }

        func handleURL(_ url: URL) {
            DispatchQueue.main.async { self.parent.onDropURL(url) }
        }
    }
}

// MARK: - AppKit ビュー（NSDraggingDestination）

private class DropReceiverNSView: NSView {
    var coordinator: AppKitDropReceiver.Coordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }

    required init?(coder: NSCoder) { fatalError() }

    // マウスクリックは透過させてボタン操作を妨げない
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    // MARK: NSDraggingDestination

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = validate(sender)
        coordinator?.setTargeted(valid)
        return valid ? .copy : []
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        return validate(sender) ? .copy : []
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        coordinator?.setTargeted(false)
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        coordinator?.setTargeted(false)
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator?.setTargeted(false)
        guard let url = fileURL(from: sender) else { return false }
        coordinator?.handleURL(url)
        return true
    }

    // MARK: Helpers

    private func validate(_ sender: NSDraggingInfo) -> Bool {
        guard let url = fileURL(from: sender) else { return false }
        guard let mode = coordinator?.mode else { return false }
        if case .folder = mode {
            var isDir: ObjCBool = false
            return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir)
                && isDir.boolValue
        }
        return true
    }

    private func fileURL(from sender: NSDraggingInfo) -> URL? {
        sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self],
                         options: [.urlReadingFileURLsOnly: true])
            .flatMap { $0 as? [URL] }?
            .first
    }
}
