import Foundation

/// ディレクトリと (あれば) その中の 1 ファイルを vnode で監視し、変化を debounce でまとめてメインキューで知らせる。
/// ディレクトリの監視は作成・改名・削除 (エディタの原子的保存 = 一時ファイルに書いて改名) を、
/// ファイルの監視はその場での書き直し (truncate + write) を捕まえる。削除・改名の後はファイルを開き直す。
/// fd は O_EVTONLY で開き、cancel handler で close する
final class FileWatcher {
    private let file: URL
    private let debounce: TimeInterval
    /// FileWatcher の生存期間中ずっと強参照で保持される。呼び出し元は自分自身を weak でキャプチャすること (AppModel はそうする)
    private let onChange: () -> Void
    private let queue = DispatchQueue(label: "FolderArt.FileWatcher")
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var pending: DispatchWorkItem?

    /// ディレクトリが開けなければ nil (無い間は監視しない)
    init?(directory: URL, file: URL, debounce: TimeInterval = 0.3, onChange: @escaping () -> Void) {
        self.file = file
        self.debounce = debounce
        self.onChange = onChange
        guard let source = Self.makeSource(path: directory.path, mask: .write, queue: queue) else { return nil }
        directorySource = source
        source.setEventHandler { [weak self] in self?.directoryChanged() }
        source.resume()
        queue.sync { watchFileIfPresent() }
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        pending?.cancel()
    }

    private static func makeSource(path: String, mask: DispatchSource.FileSystemEvent,
                                   queue: DispatchQueue) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: mask, queue: queue)
        source.setCancelHandler { close(fd) }
        return source
    }

    /// queue 上で呼ぶ。ファイルがあれば (開き直して) 監視する。無ければディレクトリの監視だけになる
    private func watchFileIfPresent() {
        fileSource?.cancel()
        fileSource = nil
        guard let source = Self.makeSource(path: file.path,
                                           mask: [.write, .extend, .attrib, .delete, .rename], queue: queue) else { return }
        fileSource = source
        source.setEventHandler { [weak self, weak source] in
            guard let self, let source else { return }
            self.fileChanged(flags: source.data)
        }
        source.resume()
    }

    private func directoryChanged() {
        watchFileIfPresent()   // 作成・改名で実体が変わったかもしれないので開き直す
        schedule()
    }

    private func fileChanged(flags: DispatchSource.FileSystemEvent) {
        if flags.contains(.delete) || flags.contains(.rename) { watchFileIfPresent() }
        schedule()
    }

    /// 連続した変化を debounce でまとめ、メインキューで 1 回だけ知らせる
    private func schedule() {
        pending?.cancel()
        let item = DispatchWorkItem { [weak self] in self?.onChange() }
        pending = item
        DispatchQueue.main.asyncAfter(deadline: .now() + debounce, execute: item)
    }
}
