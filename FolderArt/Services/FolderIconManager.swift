import AppKit
import Foundation

enum FolderIconError: LocalizedError {
    case folderNotFound(URL)
    case applyFailed(URL)
    case resetFailed(URL)

    var errorDescription: String? {
        switch self {
        case .folderNotFound(let url):
            return String(localized: "フォルダーが見つかりません: \(url.lastPathComponent)")
        case .applyFailed(let url):
            return String(localized: "アイコンを適用できません: \(url.lastPathComponent)。書き込み権限を確認してください。")
        case .resetFailed(let url):
            return String(localized: "アイコンを元に戻せません: \(url.lastPathComponent)")
        }
    }
}

class FolderIconManager {

    /// ~/Library/Application Support/FolderArt/backups
    static var defaultBackupDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("FolderArt/backups")
    }

    let backupDirectory: URL

    init(backupDirectory: URL = FolderIconManager.defaultBackupDirectory) {
        self.backupDirectory = backupDirectory
        try? FileManager.default.createDirectory(at: backupDirectory, withIntermediateDirectories: true)
    }

    /// 現在のフォルダーアイコンをバックアップして保存先 URL を返す。設定されていない場合は nil を返す。
    /// 既にバックアップがあれば **上書きしない**。2 回目の適用で FolderArt 自身の合成結果を
    /// 「元のアイコン」として記録してしまうと、リセットでユーザーの元アイコンに戻せなくなる。
    func backupCurrentIcon(for folderURL: URL) throws -> URL? {
        // Only backup if the folder *actually* has a custom icon set ("Icon\r" file exists)
        // Otherwise returning a generic blue folder image leads to a fake custom icon being restored
        let iconFile = folderURL.appendingPathComponent("Icon\r")
        if !FileManager.default.fileExists(atPath: iconFile.path) {
            return nil
        }

        let backupDir = backupFolder(for: folderURL)
        let backupURL = backupDir.appendingPathComponent("original.png")

        // 初回のバックアップだけが「ユーザーの元アイコン」。以後は再利用する
        if FileManager.default.fileExists(atPath: backupURL.path) {
            return backupURL
        }
        try FileManager.default.createDirectory(at: backupDir, withIntermediateDirectories: true)

        let currentIcon = NSWorkspace.shared.icon(forFile: folderURL.path)

        guard let tiff   = currentIcon.tiffRepresentation,
              let bitmap  = NSBitmapImageRep(data: tiff),
              let pngData = bitmap.representation(using: .png, properties: [:]) else {
            return nil
        }

        try pngData.write(to: backupURL)
        return backupURL
    }

    /// フォルダーごとのバックアップ置き場。パスをそのまま鍵にする (base64 でファイル名に使える形へ)
    func backupFolder(for folderURL: URL) -> URL {
        let folderID = folderURL.path
            .data(using: .utf8)?
            .base64EncodedString()
            .replacingOccurrences(of: "/", with: "_")
            ?? UUID().uuidString
        return backupDirectory.appendingPathComponent(folderID)
    }

    /// このフォルダーのバックアップファイルが既に存在するかどうか。
    /// 適用が失敗して巻き戻すとき、今回の適用で新たにバックアップを作ったのか
    /// 既存のものを再利用しただけなのかを判定するために使う。
    func backupExists(for folderURL: URL) -> Bool {
        let backupURL = backupFolder(for: folderURL).appendingPathComponent("original.png")
        return FileManager.default.fileExists(atPath: backupURL.path)
    }

    /// バックアップを破棄する。リセット完了後に呼ぶ。
    /// 残したままだと、ユーザーが後から別のカスタムアイコンを付けて再適用したときに
    /// 古い方が「元のアイコン」として再利用され、リセットで違うアイコンに戻ってしまう。
    func removeBackup(for folderURL: URL) {
        let dir = backupFolder(for: folderURL)
        guard FileManager.default.fileExists(atPath: dir.path) else { return }
        try? FileManager.default.removeItem(at: dir)
    }

    /// 履歴の行が持つ backupPath (…/backups/<key>/original.png) の親ディレクトリを消す。
    /// バックアップディレクトリの外を指していたら何もしない。
    func removeBackup(atBackupPath path: String?) {
        guard let path else { return }
        let dir = URL(fileURLWithPath: path).deletingLastPathComponent().standardizedFileURL
        let root = backupDirectory.standardizedFileURL.pathComponents
        // 文字列の前方一致だと "backups_evil" も通ってしまうので、パス要素単位で包含を見る
        guard dir.pathComponents.count > root.count, Array(dir.pathComponents.prefix(root.count)) == root else { return }
        try? FileManager.default.removeItem(at: dir)
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

    /// フォルダーのアイコンをバックアップ（または デフォルト）に戻す。失敗は throw。
    func resetIcon(for folderURL: URL, backupURL: URL?) throws {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: folderURL.path, isDirectory: &isDir), isDir.boolValue else {
            throw FolderIconError.folderNotFound(folderURL)
        }
        let succeeded: Bool
        if let backupURL = backupURL,
           let backupImage = NSImage(contentsOf: backupURL) {
            succeeded = NSWorkspace.shared.setIcon(backupImage, forFile: folderURL.path, options: [])
        } else {
            succeeded = NSWorkspace.shared.setIcon(nil, forFile: folderURL.path, options: [])
        }
        guard succeeded else { throw FolderIconError.resetFailed(folderURL) }
    }
}
