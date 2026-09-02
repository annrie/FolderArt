import AppKit
import Foundation

enum FolderIconError: LocalizedError {
    case folderNotFound(URL)
    case applyFailed(URL)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let url):
            return String(localized: "フォルダーが見つかりません: \(url.lastPathComponent)")
        case .applyFailed(let url):
            return String(localized: "アイコンを適用できません: \(url.lastPathComponent)。書き込み権限を確認してください。")
        }
    }
}

class FolderIconManager {

    let backupDirectory: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let dir = appSupport.appendingPathComponent("FolderArt/backups")
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }()

    /// 現在のフォルダーアイコンをバックアップして保存先 URL を返す。設定されていない場合は nil を返す
    func backupCurrentIcon(for folderURL: URL) throws -> URL? {
        // Only backup if the folder *actually* has a custom icon set ("Icon\r" file exists)
        // Otherwise returning a generic blue folder image leads to a fake custom icon being restored
        let iconFile = folderURL.appendingPathComponent("Icon\r")
        if !FileManager.default.fileExists(atPath: iconFile.path) {
            return nil
        }

        let folderID = folderURL.path
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            ?? UUID().uuidString

        let backupDir = backupDirectory.appendingPathComponent(folderID)
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let currentIcon = NSWorkspace.shared.icon(forFile: folderURL.path)
        let backupURL = backupDir.appendingPathComponent("original.png")

        guard let tiff   = currentIcon.tiffRepresentation,
              let bitmap  = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        try pngData.write(to: backupURL)
        return backupURL
    }

    /// 合成済みアイコンをフォルダーに適用する。失敗は throw。
    func applyIcon(_ icon: NSImage, to folderURL: URL) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderIconError.folderNotFound(folderURL)
        }
        // NSWorkspace.setIcon が custom icon bit を立てる。setfile は Xcode 付属で多くの Mac に無いため使わない。
        guard NSWorkspace.shared.setIcon(icon, forFile: folderURL.path, options: []) else {
            throw FolderIconError.applyFailed(folderURL)
        }
    }

    /// フォルダーのアイコンをバックアップ（または デフォルト）に戻す
    func resetIcon(for folderURL: URL, backupURL: URL?) {
        if let backupURL = backupURL,
           let backupImage = NSImage(contentsOf: backupURL) {
            NSWorkspace.shared.setIcon(backupImage, forFile: folderURL.path, options: [])
        } else {
            NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: [])
        }
    }
}
