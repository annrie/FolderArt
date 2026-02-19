import Foundation

enum BookmarkError: LocalizedError {
    case creationFailed(String)
    case resolutionFailed(String)
    case stale

    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg): return "ブックマーク作成失敗: \(msg)"
        case .resolutionFailed(let msg): return "ブックマーク解決失敗: \(msg)"
        case .stale: return "ブックマークが古くなっています"
        }
    }
}

class BookmarkManager {

    /// Security-Scoped Bookmark を作成する
    static func createBookmark(for url: URL) throws -> Data {
        do {
            let data = try url.bookmarkData(
                options: [.withSecurityScope, .securityScopeAllowOnlyReadAccess],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            )
            return data
        } catch {
            // App Sandbox 外 (テスト環境など) ではセキュリティスコープなしで試みる
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
            // セキュリティスコープなしで再試行（テスト環境対応）
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
