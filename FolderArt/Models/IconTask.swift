import Foundation

enum IconPosition: String, Codable, CaseIterable, Equatable {
    case center = "center"
    case badge  = "badge"

    var displayName: String {
        switch self {
        case .center: return "中央オーバーレイ"
        case .badge:  return "右下バッジ"
        }
    }
}

struct IconTask: Codable, Identifiable, Equatable {
    let id: UUID
    let folderPath: String
    let bookmarkData: Data
    let appliedAt: Date
    let backupPath: String
    let imageName: String
    let position: IconPosition
    let scale: Double
    let opacity: Double
    let verticalOffset: Double
    let clipToFolderShape: Bool

    init(
        id: UUID = UUID(),
        folderPath: String,
        bookmarkData: Data,
        appliedAt: Date = Date(),
        backupPath: String,
        imageName: String,
        position: IconPosition,
        scale: Double,
        opacity: Double,
        verticalOffset: Double = 0.0,
        clipToFolderShape: Bool = true
    ) {
        self.id = id
        self.folderPath = folderPath
        self.bookmarkData = bookmarkData
        self.appliedAt = appliedAt
        self.backupPath = backupPath
        self.imageName = imageName
        self.position = position
        self.scale = scale
        self.opacity = opacity
        self.verticalOffset = verticalOffset
        self.clipToFolderShape = clipToFolderShape
    }
}
