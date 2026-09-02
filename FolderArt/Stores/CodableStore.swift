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
}
