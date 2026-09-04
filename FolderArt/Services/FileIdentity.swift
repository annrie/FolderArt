import Foundation

/// フォルダの同一性: ボリューム UUID とファイル ID の組。同一ボリューム内の改名・移動で不変。
/// コピーや別ボリュームへの移動、作り直しは別物になる (呼び出し側は path 比較に落ちる)。
enum FileIdentity {
    static func make(for url: URL) -> String? {
        guard let values = try? url.resourceValues(forKeys: [.volumeUUIDStringKey, .fileResourceIdentifierKey]),
              let volume = values.volumeUUIDString,
              let identifier = values.fileResourceIdentifier else { return nil }
        let fileID: String
        if let data = identifier as? Data {
            fileID = data.base64EncodedString()
        } else if let number = identifier as? NSNumber {
            fileID = number.stringValue
        } else {
            return nil
        }
        return "\(volume):\(fileID)"
    }
}
