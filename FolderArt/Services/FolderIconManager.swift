import AppKit
import Foundation

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

    /// 現在のフォルダーアイコンをバックアップして保存先 URL を返す
    func backupCurrentIcon(for folderURL: URL) throws -> URL? {
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

    /// 合成済みアイコンをフォルダーに適用する
    @discardableResult
    func applyIcon(_ icon: NSImage, to folderURL: URL) -> Bool {
        return NSWorkspace.shared.setIcon(icon, forFile: folderURL.path, options: [])
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
