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
        guard let volume = try? url.resourceValues(forKeys: [.volumeUUIDStringKey]).volumeUUIDString,
              let attributes = try? FileManager.default.attributesOfItem(atPath: url.path),
              let inode = (attributes[.systemFileNumber] as? NSNumber)?.uint64Value else { return nil }
        return "\(volume):\(inode)"
    }
}
