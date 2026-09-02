import SwiftUI
import UniformTypeIdentifiers
import AppKit

struct DropZoneView: View {
    enum Mode {
        case folder
        case image
    }

    let mode: Mode
    let onDropURLs: ([URL]) -> Void
    let onTapButton: () -> Void

    @State private var isTargeted = false
    private let displayURL: URL?
    private let previewImage: NSImage?

    init(
        mode: Mode,
        selectedURL: URL?,
        previewImage: NSImage?,
        onDropURLs: @escaping ([URL]) -> Void,
        onTapButton: @escaping () -> Void
    ) {
        self.mode = mode
        self.displayURL = selectedURL
        self.previewImage = previewImage
        self.onDropURLs = onDropURLs
        self.onTapButton = onTapButton
    }

    static func isDirectory(_ url: URL) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) && isDir.boolValue
    }

    static func isImage(_ url: URL) -> Bool {
        guard let type = UTType(filenameExtension: url.pathExtension) else { return false }
        return type.conforms(to: .image)
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
            FileDropReceiver(
                isTargeted: $isTargeted,
                accepts: { urls in
                    switch mode {
                    case .folder: return urls.contains(where: Self.isDirectory)
                    case .image:  return urls.contains(where: Self.isImage)
                    }
                },
                onDrop: { urls in
                    switch mode {
                    case .folder: onDropURLs(urls.filter(Self.isDirectory))
                    case .image:  onDropURLs(urls.filter(Self.isImage))
                    }
                }
            )
        )
        .padding(4)
    }
}

// MARK: - AppKit D&D レシーバー (再利用可能)

/// SwiftUI の onDrop は macOS で信頼性が低いため、NSView で .fileURL を受ける。
/// クリックは透過させる (hitTest = nil) ので、下のボタン操作を妨げない。
struct FileDropReceiver: NSViewRepresentable {
    @Binding var isTargeted: Bool
    let accepts: ([URL]) -> Bool
    let onDrop: ([URL]) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeNSView(context: Context) -> DropReceiverNSView {
        let view = DropReceiverNSView()
        view.coordinator = context.coordinator
        return view
    }

    func updateNSView(_ nsView: DropReceiverNSView, context: Context) {
        context.coordinator.parent = self
    }

    final class Coordinator {
        var parent: FileDropReceiver
        init(_ parent: FileDropReceiver) { self.parent = parent }

        func accepts(_ urls: [URL]) -> Bool { parent.accepts(urls) }
        func setTargeted(_ value: Bool) { DispatchQueue.main.async { self.parent.isTargeted = value } }
        func handle(_ urls: [URL]) { DispatchQueue.main.async { self.parent.onDrop(urls) } }
    }
}

final class DropReceiverNSView: NSView {
    var coordinator: FileDropReceiver.Coordinator?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        registerForDraggedTypes([.fileURL])
    }
    required init?(coder: NSCoder) { fatalError() }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        let valid = validate(sender)
        coordinator?.setTargeted(valid)
        return valid ? .copy : []
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        validate(sender) ? .copy : []
    }
    override func draggingExited(_ sender: NSDraggingInfo?) { coordinator?.setTargeted(false) }
    override func draggingEnded(_ sender: NSDraggingInfo) { coordinator?.setTargeted(false) }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        coordinator?.setTargeted(false)
        let urls = fileURLs(from: sender)
        guard !urls.isEmpty, coordinator?.accepts(urls) == true else { return false }
        coordinator?.handle(urls)
        return true
    }

    private func validate(_ sender: NSDraggingInfo) -> Bool {
        let urls = fileURLs(from: sender)
        return !urls.isEmpty && (coordinator?.accepts(urls) ?? false)
    }

    /// ドロップされた **全件** の file URL
    private func fileURLs(from sender: NSDraggingInfo) -> [URL] {
        sender.draggingPasteboard
            .readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true])
            .flatMap { $0 as? [URL] } ?? []
    }
}
