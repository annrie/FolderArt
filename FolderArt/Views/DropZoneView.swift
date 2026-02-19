import SwiftUI
import UniformTypeIdentifiers

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

    init(
        mode: Mode,
        selectedURL: URL?,
        onDropURL: @escaping (URL) -> Void,
        onTapButton: @escaping () -> Void
    ) {
        self.mode = mode
        self.displayURL = selectedURL
        self.onDropURL = onDropURL
        self.onTapButton = onTapButton
    }

    private var acceptedTypes: [UTType] {
        switch mode {
        case .folder: return [.folder]
        case .image:  return [.png, .jpeg, .heic, .gif, .webP, .image]
        }
    }

    private var icon: String {
        switch mode {
        case .folder: return "folder.fill"
        case .image:  return "photo.fill"
        }
    }

    private var label: String {
        switch mode {
        case .folder: return "フォルダーをここにドロップ"
        case .image:  return "画像をここにドロップ"
        }
    }

    private var buttonLabel: String {
        switch mode {
        case .folder: return "フォルダーを選択..."
        case .image:  return "画像を選択..."
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 36))
                .foregroundColor(isTargeted ? .accentColor : .secondary)

            Text(label)
                .font(.callout)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)

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
        .onDrop(of: acceptedTypes, isTargeted: $isTargeted) { providers in
            guard let provider = providers.first else { return false }
            let typeID: String
            switch mode {
            case .folder: typeID = UTType.folder.identifier
            case .image:  typeID = UTType.fileURL.identifier
            }
            provider.loadItem(forTypeIdentifier: typeID, options: nil) { item, _ in
                guard let data = item as? Data,
                      let url = URL(dataRepresentation: data, relativeTo: nil) else { return }
                DispatchQueue.main.async { onDropURL(url) }
            }
            return true
        }
        .padding(4)
    }
}
