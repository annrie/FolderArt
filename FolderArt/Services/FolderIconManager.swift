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

    /// 合成済みアイコンをフォルダーに適用する
    @discardableResult
    func applyIcon(_ icon: NSImage, to folderURL: URL) -> Bool {
        let success = NSWorkspace.shared.setIcon(icon, forFile: folderURL.path, options: [])
        if success {
            // macOS relies on the Custom Icon bit (hasCustomIcon). NSWorkspace usually sets it,
            // but iCloud might strip it. Force setting it via `setfile` command as a fallback.
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/setfile")
            process.arguments = ["-a", "C", folderURL.path]
            try? process.run()
        }
        return success
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
