import Foundation

enum BookmarkError: LocalizedError {
    case creationFailed(String)
    case resolutionFailed(String)
    case stale

    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg):   return String(localized: "ブックマーク作成失敗: \(msg)")
        case .resolutionFailed(let msg): return String(localized: "ブックマーク解決失敗: \(msg)")
        case .stale:                     return String(localized: "ブックマークが古くなっています")
        }
    }
}

class BookmarkManager {

    /// App Sandbox 内で実行中かどうか。サンドボックス化されたアプリのプロセス環境変数には
    /// Launch Services がこのキーを必ず設定する。単体テストはこのアプリ自身をホストとして
    /// 実行されるため、テストプロセスでも true になる (テスト対象の FolderArt.entitlements
    /// が app-sandbox を有効にしているため)。それでも既存のラウンドトリップテストが通るのは、
    /// テストが使う一時ディレクトリがサンドボックスコンテナ内にありアクセス可能なので、
    /// セキュリティスコープ付きの作成/解決がフォールバックに頼らず素通りで成功するため。
    static var isSandboxed: Bool {
        ProcessInfo.processInfo.environment["APP_SANDBOX_CONTAINER_ID"] != nil
    }

    /// Security-Scoped Bookmark を作成する
    static func createBookmark(for url: URL) throws -> Data {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            // サンドボックス内ではセキュリティスコープなしのブックマークは再起動後に
            // 書き込みアクセスを復元できず無意味 (かつ履歴の Reset を誤って有効にしてしまう)
            // なので使わない。App Sandbox 外でビルド/実行された場合にのみフォールバックする
            guard !isSandboxed else {
                throw BookmarkError.creationFailed(error.localizedDescription)
            }
            do {
                let data = try url.bookmarkData(
                    options: [],
                    includingResourceValuesForKeys: nil,
                    relativeTo: nil
                )
                return data
            } catch {
                throw BookmarkError.creationFailed(error.localizedDescription)
            }
        }
    }

    /// Security-Scoped Bookmark を解決して URL を返す
    static func resolveBookmark(_ data: Data) throws -> URL {
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: data,
                options: [.withSecurityScope],
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            if isStale { throw BookmarkError.stale }
            return url
        } catch let error as BookmarkError {
            throw error
        } catch {
            // 作成時と同じ理由で、サンドボックス内ではセキュリティスコープなしの解決を試みない
            guard !isSandboxed else {
                throw BookmarkError.resolutionFailed(error.localizedDescription)
            }
            // セキュリティスコープなしで再試行（App Sandbox 外での実行対応）
            var isStale2 = false
            do {
                let url = try URL(
                    resolvingBookmarkData: data,
                    options: [],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale2
                )
                return url
            } catch {
                throw BookmarkError.resolutionFailed(error.localizedDescription)
            }
        }
    }
}
