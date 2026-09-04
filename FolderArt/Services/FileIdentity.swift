import Foundation

/// フォルダの同一性: ボリューム UUID と inode 番号の組。同一ボリューム内の改名・移動で不変。
/// コピーや別ボリュームへの移動、作り直しは別物になる (呼び出し側は path 比較に落ちる)。
///
/// `fileResourceIdentifierKey` は使わない: inode に加えてマウント時に決まるファイルシステム ID を含み、
/// 再起動や外付けボリュームの抜き差しをまたぐと値が変わる (Apple の文書でも
/// "not persistent across system restarts")。履歴は起動をまたいで残るので、
/// APFS / HFS+ で安定している inode 番号 (`systemFileNumber`) を使う。
enum FileIdentity {
    static func make(for url: URL) -> String? {
        // シンボリックリンク経由でも同じフォルダは同じ ID にする (attributesOfItem はリンク自身の inode を返す)
        let resolved = url.resolvingSymlinksInPath()
        guard let volume = try? resolved.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
              let attributes = try? FileManager.default.attributesOfItem(atPath: resolved.path),
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        // inode は削除後に別のフォルダへ再利用されうるので、作成日時 (改名・移動では変わらない) も鍵に含める
        let created = (attributes[.creationDate] as? Date).map { Int($0.timeIntervalSince1970) } ?? 0
        return "\(volume):\(inode):\(created)"
    }
}
