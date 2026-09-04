import Foundation

enum IconPosition: String, Codable, CaseIterable, Equatable, Sendable {
    case center = "center"
    case badge  = "badge"

    var displayName: String {
        switch self {
        case .center: return String(localized: "中央オーバーレイ")
        case .badge:  return String(localized: "右下バッジ")
        }
    }
}

struct IconTask: Codable, Identifiable, Equatable, Sendable {
    static let currentVersion = 2

    let version: Int
    let id: UUID
    let folderPath: String
    let bookmarkData: Data
    let appliedAt: Date
    let backupPath: String?
    let overlay: Overlay
    let settings: CompositionSettings
    let fileID: String?

    init(
        id: UUID = UUID(),
        folderPath: String,
        bookmarkData: Data,
        appliedAt: Date = Date(),
        backupPath: String?,
        overlay: Overlay,
        settings: CompositionSettings,
        fileID: String? = nil
    ) {
        self.version = Self.currentVersion
        self.id = id
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.appliedAt = appliedAt
        self.backupPath = backupPath
        self.overlay = overlay
        self.settings = settings
        self.fileID = fileID
    }

    /// backupPath だけ差し替えたコピーを返す (upsert でのバックアップ引き継ぎ用)
    func withBackupPath(_ path: String?) -> IconTask {
        IconTask(id: id, folderPath: folderPath, bookmarkData: bookmarkData, appliedAt: appliedAt,
                 backupPath: path, overlay: overlay, settings: settings, fileID: fileID)
    }

    private enum CodingKeys: String, CodingKey {
        case version, id, folderPath, bookmarkData, appliedAt, backupPath, overlay, settings, fileID
        // v1 only
        case imageName, position, scale, opacity, verticalOffset, clipToFolderShape
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id           = try c.decode(UUID.self,   forKey: .id)
        folderPath   = try c.decode(String.self, forKey: .folderPath)
        bookmarkData = try c.decode(Data.self,   forKey: .bookmarkData)
        appliedAt    = try c.decode(Date.self,   forKey: .appliedAt)
        let rawBackup = try c.decodeIfPresent(String.self, forKey: .backupPath)
        backupPath   = (rawBackup?.isEmpty ?? true) ? nil : rawBackup
        fileID       = try c.decodeIfPresent(String.self, forKey: .fileID)
        version      = Self.currentVersion

        if let v = try c.decodeIfPresent(Int.self, forKey: .version), v >= 2 {
            overlay  = try c.decode(Overlay.self, forKey: .overlay)
            settings = try c.decode(CompositionSettings.self, forKey: .settings)
        } else {
            // v1: 平置きの設定と imageName
            let name = try c.decodeIfPresent(String.self, forKey: .imageName) ?? ""
            overlay = .legacyImage(name: name)
            var s = CompositionSettings()
            s.position          = try c.decodeIfPresent(IconPosition.self, forKey: .position) ?? s.position
            s.scale             = try c.decodeIfPresent(Double.self, forKey: .scale) ?? s.scale
            s.opacity           = try c.decodeIfPresent(Double.self, forKey: .opacity) ?? s.opacity
            s.verticalOffset    = try c.decodeIfPresent(Double.self, forKey: .verticalOffset) ?? s.verticalOffset
            s.clipToFolderShape = try c.decodeIfPresent(Bool.self, forKey: .clipToFolderShape) ?? s.clipToFolderShape
            settings = s
        }
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(version,      forKey: .version)
        try c.encode(id,           forKey: .id)
        try c.encode(folderPath,   forKey: .folderPath)
        try c.encode(bookmarkData, forKey: .bookmarkData)
        try c.encode(appliedAt,    forKey: .appliedAt)
        try c.encodeIfPresent(backupPath, forKey: .backupPath)
        try c.encode(overlay,      forKey: .overlay)
        try c.encode(settings,     forKey: .settings)
        try c.encodeIfPresent(fileID, forKey: .fileID)
    }
}
