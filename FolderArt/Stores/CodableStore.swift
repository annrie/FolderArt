import Foundation

/// 1 つの JSON ファイルに 1 つの Codable 値を読み書きする。失敗は throws で返す。
struct CodableStore<T: Codable> {
    let fileURL: URL

    /// ファイルが無ければ nil。壊れていれば throw。
    func load() throws -> T? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(T.self, from: data)
    }

    func save(_ value: T) throws {
        try FileManager.default.createDirectory(
            at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(value)
        try data.write(to: fileURL, options: .atomic)
    }

    /// 読めなかったファイルを `<name>.corrupt-<yyyyMMdd-HHmmss>` に退避して新しい URL を返す。
    /// ファイルが無ければ nil。次の save が中身を黙って消してしまうのを防ぐ。
    @discardableResult
    func quarantineIfPresent() throws -> URL? {
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        let base = fileURL.lastPathComponent + ".corrupt-" + formatter.string(from: Date())
        let directory = fileURL.deletingLastPathComponent()

        var target = directory.appendingPathComponent(base)
        var suffix = 2
        while FileManager.default.fileExists(atPath: target.path) {   // 同じ秒に 2 回来た場合
            target = directory.appendingPathComponent("\(base)-\(suffix)")
            suffix += 1
        }
        try FileManager.default.moveItem(at: fileURL, to: target)
        return target
    }
}
