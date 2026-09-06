import AppKit
import Combine
import CryptoKit
import SwiftUI
import UniformTypeIdentifiers
import os

/// 画面全体の状態を束ねる。個別の責務は FolderSelection / OverlayState / ApplyCoordinator が持つ。
@MainActor
final class AppModel: ObservableObject {
    let folders: FolderSelection
    let overlay: OverlayState
    let history: HistoryStore
    let presets: PresetStore
    let assets: AssetStore
    private let lastPresetStore: LastPresetStore
    private let coordinator: ApplyCoordinator

    @Published var errorMessage: String?
    @Published var isApplying = false
    /// パックの読み込み中 (多重起動しない)
    private var isImportingPack = false
    @Published var progress: (done: Int, total: Int)?
    /// 提案 (フォルダ名と中身から)。空なら帯はチップ無しで高さだけ保つ
    @Published private(set) var suggestions: [Suggestion] = []
    /// 提案エンジン。ユーザー辞書が変わると作り直す
    private(set) var suggestionEngine: SuggestionEngine
    private let bundledDictionary: SuggestionDictionary
    private let catalog: SymbolCatalog
    /// ユーザー辞書 (suggestions-user.json)。テストでは一時ディレクトリを注入する
    let userDictionaryURL: URL
    private var dictionaryWatcher: FileWatcher?
    /// 読み込みの世代。監視の通知が重なっても最後の 1 回の結果だけ採る
    private var dictionaryGeneration = 0
    /// 直近に失敗したユーザー辞書の内容の SHA-256。同じ内容では二度アラートを出さない
    private var lastDictionaryErrorHash: Data?
    /// 中身の走査 (テストで差し替える)。メインの外で呼ばれる
    typealias ContentScannerFunction = @Sendable (URL) -> ContentSummary?
    private let scanContents: ContentScannerFunction
    /// 最後に走査したフォルダとその結果 (summary nil = 読めなかった)。対象が変わるまで使い回す
    private var contentSummary: (folder: URL, summary: ContentSummary?)?
    private var contentScanTask: Task<Void, Never>?
    /// 走査の世代。戻ってきた結果がこれと違えば捨てる (同じ URL を外して入れ直した場合も新しい世代だけ採る)
    private var scanGeneration = 0
    private var scanningFolder: URL?
    private var cancellables: Set<AnyCancellable> = []
    /// 履歴から開いたセキュリティスコープ。鍵は標準化した URL、値はスコープを持つ URL 本体
    /// (stop は start を呼んだ URL に対して呼ぶ必要がある)
    private var scopedURLs: [URL: URL] = [:]

    /// テスト用: 開きっぱなしのスコープの数
    var scopedURLCount: Int { scopedURLs.count }

    init(history: HistoryStore = HistoryStore(),
         presets: PresetStore = PresetStore(),
         assets: AssetStore = AssetStore(),
         dictionary bundledDictionary: SuggestionDictionary = SuggestionDictionary.load(),
         catalog: SymbolCatalog = SymbolCatalog.shared,
         userDictionaryURL: URL = HistoryStore.appSupportDirectory.appendingPathComponent(SuggestionDictionary.userFileName),
         contentScanner: @escaping ContentScannerFunction = { ContentScanner.scan($0) },
         lastPresetStore: LastPresetStore = LastPresetStore(),
         runsMaintenance: Bool = true) {
        self.history = history
        self.presets = presets
        self.assets = assets
        self.lastPresetStore = lastPresetStore
        self.bundledDictionary = bundledDictionary
        self.catalog = catalog
        self.userDictionaryURL = userDictionaryURL
        self.suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
        self.scanContents = contentScanner
        self.folders = FolderSelection()
        self.overlay = OverlayState(assets: assets)
        self.coordinator = ApplyCoordinator(history: history)

        // 子オブジェクトの変更を自分の変更として流し、ContentView を再描画させる
        for child in [folders.objectWillChange.eraseToAnyPublisher(),
                      overlay.objectWillChange.eraseToAnyPublisher(),
                      history.objectWillChange.eraseToAnyPublisher(),
                      presets.objectWillChange.eraseToAnyPublisher()] {
            child.sink { [weak self] _ in self?.objectWillChange.send() }.store(in: &cancellables)
        }

        // リストから消えたフォルダのスコープは閉じる (再適用のたびに開きっぱなしにしない)
        folders.$folders
            .sink { [weak self] list in self?.releaseScopes(keeping: list) }
            .store(in: &cancellables)

        if let e = history.loadError ?? presets.loadError {
            errorMessage = String(localized: "保存データの読み込みに失敗しました: \(e.localizedDescription)")
        }

        // フォルダの増減・選択・お気に入りの変化で提案を作り直す (同期・純関数なのでデバウンス不要)。
        // @Published の $プロパティは willSet 側で発火するため、ここで self.folders.folders 等を
        // 読み直すと更新前の値をつかんでしまう。クロージャに渡された最新値だけを使う。
        Publishers.CombineLatest3(folders.$folders, folders.$selectedIDs, presets.$presets)
            .sink { [weak self] folders, selectedIDs, presets in
                self?.refreshSuggestions(folders: folders, selectedIDs: selectedIDs, presets: presets)
            }
            .store(in: &cancellables)

        // ユーザー辞書: ディレクトリがあれば監視を始め、初回を読む (メインの外で。結果はメインで反映)。
        // 世代は Task { } の実行を待たずここで同期的に確保する (reloadUserDictionary() 参照)
        startDictionaryWatcher()
        dictionaryGeneration += 1
        let initialDictionaryGeneration = dictionaryGeneration
        Task { [weak self] in await self?.performDictionaryReload(generation: initialDictionaryGeneration) }

        reapAssets()

        // 起動時の掃除はメインの外で。履歴が読めていない起動ではバックアップを消さない。
        // now には起動時刻を渡し、これ以降 (=今のセッションで) 作られたバックアップは消さない
        if runsMaintenance {
            let referenced = Set(history.tasks.compactMap(\.backupPath))
            let historyLoaded = history.loadError == nil
            let backups = FolderIconManager.defaultBackupDirectory
            let appSupport = HistoryStore.appSupportDirectory
            let launched = Date()
            Task.detached(priority: .background) { [weak self] in
                // 候補の列挙と隔離ファイルの削除はメインの外で。
                // history.json の隔離ファイルが残っている間は今の履歴を「全部」とは信じない (バックアップは触らない)
                let trusted = historyLoaded && !MaintenanceSweep.hasHistoryQuarantine(in: appSupport)
                let candidates = MaintenanceSweep.backupCandidates(referencedBackupPaths: referenced, historyLoaded: trusted,
                                                                    backupDirectory: backups, now: launched)
                let corrupt = MaintenanceSweep.removeOldCorruptFiles(in: appSupport, now: launched)
                // バックアップの片付け (ゴミ箱へ) だけはメインアクターで、最新の履歴と照合してから行う
                // (列挙中に適用が既存のバックアップを再利用して履歴に載せることがあるため)
                let removed = await self?.removeUnreferencedBackups(candidates) ?? 0
                if removed > 0 || corrupt > 0 {
                    Logger(subsystem: Bundle.main.bundleIdentifier ?? "FolderArt", category: "maintenance")
                        .info("sweep: removed \(removed) backup(s), \(corrupt) corrupt file(s)")
                }
            }
        }
    }

    /// 起動時の掃除の片付け段階。適用中なら見送る (適用が再利用したバックアップを消さないため。次回起動で改めて掃除する)
    private func removeUnreferencedBackups(_ candidates: [URL]) -> Int {
        guard !candidates.isEmpty, !isApplying else { return 0 }
        let referencedNow = Set(history.tasks.compactMap(\.backupPath))
        return MaintenanceSweep.removeBackupDirectories(candidates, stillReferencedBackupPaths: referencedNow).count
    }

    // MARK: - 適用

    var canApply: Bool { !folders.isEmpty && overlay.canApply && !isApplying }

    var applyButtonTitle: String {
        let n = folders.targets.count
        if isApplying { return String(localized: "適用中…") }
        return folders.selectedIDs.isEmpty
            ? String(localized: "\(n) フォルダに適用")
            : String(localized: "選択した \(n) フォルダに適用")
    }

    func apply() async {
        // 連打などで二重に呼ばれても 1 バッチしか走らせない (途中の yield で交錯すると
        // 先に終わった方が isApplying を下ろし、残りのバッチ中にリスト操作が解禁されてしまう)
        guard !isApplying else { return }
        // デバウンス待ちで overlayImage が古いままだと、適用と履歴で違うオーバーレイになりうる。
        // 同期描画済みなら updatePreviewNow() は何もしない (lastRendered* ガードで冪等)。
        overlay.updatePreviewNow()
        guard let overlayValue = overlay.overlay, let image = overlay.overlayImage else { return }
        let targets = folders.targets
        guard !targets.isEmpty else { return }
        isApplying = true
        progress = (0, targets.count)
        defer { isApplying = false; progress = nil }

        let outcome = await coordinator.apply(
            overlayImage: image, overlay: overlayValue, settings: overlay.settings,
            to: targets, progress: { [weak self] done, total in self?.progress = (done, total) })
        // 全件成功なら静かに終わる (既に出ているアラートを消さない)
        if let summary = outcome.summary { errorMessage = summary }
        // reapAssets() は isApplying 中は何もしないので、defer の実行を待たずここで明示的に倒しておく
        isApplying = false
        reapAssets()
    }

    // MARK: - リセット

    /// 適用先のうち FolderArt が適用した (履歴に行がある) フォルダが 1 つでもあれば戻せる
    var canReset: Bool {
        !isApplying && folders.targets.contains { hasHistory($0) }
    }

    /// 適用先 (選択 or 全部) のうち、FolderArt が適用したフォルダだけアイコンを戻す
    func resetTargets() {
        guard !isApplying else { return }
        for url in folders.targets where hasHistory(url) {
            do { try coordinator.reset(folder: url) }
            catch { errorMessage = error.localizedDescription }
        }
        reapAssets()
    }

    /// 移動・改名したフォルダも fileID で見つける (履歴の行は古い path のままでもリセットできる)
    private func hasHistory(_ url: URL) -> Bool {
        history.task(forFolderPath: url.standardizedFileURL.path, fileID: FileIdentity.make(for: url)) != nil
    }

    func reset(task: IconTask) {
        guard !isApplying else { return }
        do { try coordinator.reset(task) }
        catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    // MARK: - フォルダと画像の入力

    func addFolders(_ urls: [URL]) {
        guard !isApplying else { return }
        folders.add(urls)
    }

    func selectFoldersWithPanel() {
        guard !isApplying else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "追加")
        if panel.runModal() == .OK { folders.add(panel.urls) }
    }

    func selectImageWithPanel() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.png, .jpeg, .heic, .gif, .webP, .tiff]
        panel.prompt = String(localized: "画像を選択")
        if panel.runModal() == .OK, let url = panel.url { selectImage(url) }
    }

    func selectImage(_ url: URL) {
        do { try overlay.selectImage(url: url) }
        catch { errorMessage = error.localizedDescription }
    }

    /// ドロップされた URL をフォルダと画像に振り分ける。画像は最初の 1 枚だけ使う。
    func handleDroppedURLs(_ urls: [URL]) {
        guard !isApplying else { return }
        var dirs: [URL] = []
        var firstImage: URL?
        for url in urls {
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir) else { continue }
            if isDir.boolValue {
                dirs.append(url)
            } else if firstImage == nil, let type = UTType(filenameExtension: url.pathExtension), type.conforms(to: .image) {
                firstImage = url
            }
        }
        if !dirs.isEmpty { folders.add(dirs) }
        if let image = firstImage { selectImage(image) }
    }

    // MARK: - 提案

    /// 提案の元になるフォルダ: 選択があれば選択中のうちリスト順で最後のもの、無ければ最後に追加した行
    var suggestionSourceFolder: URL? {
        Self.suggestionSourceFolder(folders: folders.folders, selectedIDs: folders.selectedIDs)
    }

    private static func suggestionSourceFolder(folders: [URL], selectedIDs: Set<URL>) -> URL? {
        let selected = folders.filter { selectedIDs.contains($0) }
        return selected.last ?? folders.last
    }

    /// CombineLatest3 のクロージャから渡された最新値だけを使って提案を作り直す
    /// (self.folders 等を読み直すと willSet 発火時点の更新前の値になりうるため)。
    /// 名前からの候補は同期で即時。中身は対象フォルダが変わったときだけ非同期で走査し、戻ったら作り直す
    private func refreshSuggestions(folders: [URL], selectedIDs: Set<URL>, presets: [Preset]) {
        guard let folder = Self.suggestionSourceFolder(folders: folders, selectedIDs: selectedIDs) else {
            suggestions = []
            cancelContentScan()
            contentSummary = nil
            return
        }
        // 走査中に対象が (キャッシュ命中などで) 他のフォルダへ戻ると、下の start 条件が false のままになり
        // scanningFolder が古い対象を指し続けてしまう。対象が変わったらここで無条件に cancel する
        if let scanning = scanningFolder, scanning != folder { cancelContentScan() }
        let content = contentSummary?.folder == folder ? contentSummary?.summary : nil
        suggestions = suggestionEngine.suggest(for: folder.lastPathComponent, presets: presets, content: content)
        // 対象が変わったときだけ走査する (お気に入りの変化では走査し直さない)
        if contentSummary?.folder != folder, scanningFolder != folder {
            startContentScan(for: folder)
        }
    }

    private func cancelContentScan() {
        contentScanTask?.cancel()
        contentScanTask = nil
        scanningFolder = nil
    }

    /// cancel は best effort (列挙のループでは効くが、サムネイル 1 枚分は途中で止まらない)。
    /// 古い結果を採らないことは generation と対象フォルダの照合で保証する
    private func startContentScan(for folder: URL) {
        cancelContentScan()
        scanGeneration += 1
        let generation = scanGeneration
        scanningFolder = folder
        let scan = scanContents
        contentScanTask = Task.detached(priority: .utility) { [weak self] in
            let summary = scan(folder)
            guard let self else { return }
            await MainActor.run {
                guard self.scanGeneration == generation else { return }
                // 世代は最新でも対象がもう違うなら結果は棄却する。ただし scanningFolder / contentScanTask は
                // ここで戻しておかないと、対象が古いフォルダに一致してしまったとき二度と走査されなくなる
                guard self.suggestionSourceFolder == folder else {
                    self.scanningFolder = nil
                    self.contentScanTask = nil
                    return
                }
                self.contentSummary = (folder, summary)
                self.scanningFolder = nil
                self.contentScanTask = nil
                self.refreshSuggestions(folders: self.folders.folders, selectedIDs: self.folders.selectedIDs,
                                        presets: self.presets.presets)
            }
        }
    }

    /// 候補を採用する。記号・絵文字・文字はタブと入力だけ変え、設定は触らない。お気に入りは設定まで復元。
    func applySuggestion(_ suggestion: Suggestion) {
        guard !isApplying else { return }
        switch suggestion.kind {
        case .symbol(let name): overlay.activeTab = .symbol; overlay.symbolName = name
        case .emoji(let e):     overlay.activeTab = .emoji;  overlay.emoji = e
        case .text(let t):      overlay.activeTab = .text;   overlay.text = t
        case .preset(let p):    applyPreset(p)
        case .image(let r):     selectImage(r.url)
        }
    }

    // MARK: - ユーザー辞書

    static let revealUserDictionaryNotification = Notification.Name("FolderArt.revealUserDictionary")

    /// ユーザー辞書を読み直して提案エンジンを差し替える。読み込みと復号はメインの外、差し替えはメイン。
    /// 世代番号で古い結果を捨てる (監視の通知が重なっても最後の 1 回だけ採る)。中身の走査結果は使い回す。
    /// 世代の確保 (dictionaryGeneration += 1) はここで同期的に行う。init の初回読み込みも
    /// (Task { } の実行を待たず) 同じタイミングで世代を確保するため、明示的な呼び出しと初回読み込みが
    /// 競合しても「呼ばれた順」どおりに新しい方が勝つ (Task の実行順序に依存しない)
    func reloadUserDictionary() async {
        dictionaryGeneration += 1
        await performDictionaryReload(generation: dictionaryGeneration)
    }

    /// 実際の読み込みと差し替え。generation は呼び出し側 (reloadUserDictionary / init) が
    /// 同期的に採番したものを渡す。世代は呼び出し側が同期的に確保する
    /// (Task 開始の遅延で順序が入れ替わるのを防ぐ)
    private func performDictionaryReload(generation: Int) async {
        let url = userDictionaryURL
        let loaded = await Task.detached(priority: .utility) { () -> (result: Result<SuggestionDictionary, Error>?, hash: Data?) in
            let result = SuggestionDictionary.loadUser(at: url)
            // 失敗したときだけ、同じ内容で二度アラートを出さないための指紋を取る
            var hash: Data?
            if case .failure(let error) = result { hash = Self.dictionaryErrorFingerprint(url: url, error: error) }
            return (result, hash)
        }.value
        guard generation == dictionaryGeneration else { return }

        switch loaded.result {
        case nil:
            suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
            lastDictionaryErrorHash = nil
        case .success(let user):
            suggestionEngine = SuggestionEngine(dictionary: .merging(user: user, bundled: bundledDictionary), catalog: catalog)
            lastDictionaryErrorHash = nil
        case .failure(let error):
            suggestionEngine = SuggestionEngine(dictionary: bundledDictionary, catalog: catalog)
            if loaded.hash != lastDictionaryErrorHash {
                lastDictionaryErrorHash = loaded.hash
                report(String(localized: "提案辞書を読めません: \(error.localizedDescription)"))
            }
        }
        refreshSuggestions(folders: folders.folders, selectedIDs: folders.selectedIDs, presets: presets.presets)
    }

    /// 壊れた辞書の指紋。上限以内で読めれば中身の SHA-256、超過や読めないときはサイズとエラー文から作る (必ず値を返す)。
    /// detached タスクから呼べるよう nonisolated にする (メインアクター状態には触れない)
    nonisolated static func dictionaryErrorFingerprint(url: URL, error: Error) -> Data {
        let size = ((try? FileManager.default.attributesOfItem(atPath: url.path)[.size]) as? NSNumber)?.intValue ?? -1
        if size >= 0, size <= SuggestionDictionary.userMaxFileBytes, let data = try? Data(contentsOf: url) {
            return Data(SHA256.hash(data: data))
        }
        return Data(SHA256.hash(data: Data("\(size):\(error.localizedDescription)".utf8)))
    }

    /// 既に出ているアラート (起動時の保存データのエラーなど) があれば、その後ろに空行を挟んで連結する
    private func report(_ message: String) {
        if let current = errorMessage, !current.isEmpty {
            errorMessage = current + "\n\n" + message
        } else {
            errorMessage = message
        }
    }

    /// ディレクトリがあるときだけ監視する (無い間は「提案辞書を開く…」で作ったときに始める)。通知のたびに必ず読み直す
    private func startDictionaryWatcher() {
        guard dictionaryWatcher == nil else { return }
        let directory = userDictionaryURL.deletingLastPathComponent()
        dictionaryWatcher = FileWatcher(directory: directory, file: userDictionaryURL) { [weak self] in
            Task { await self?.reloadUserDictionary() }
        }
    }

    /// ユーザー辞書のファイルを (無ければディレクトリごと作って雛形で) 用意し、監視を始める。Finder 表示はしない
    @discardableResult
    func prepareUserDictionaryFile() throws -> URL {
        let directory = userDictionaryURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        // 監視はディレクトリができた直後・雛形を書く前に始める (書き込みイベントを取りこぼさないため)
        startDictionaryWatcher()
        if !FileManager.default.fileExists(atPath: userDictionaryURL.path) {
            try SuggestionDictionary.userTemplate.write(to: userDictionaryURL, atomically: true, encoding: .utf8)
        }
        return userDictionaryURL
    }

    /// 「ファイル > 提案辞書を開く…」: ファイルを用意して Finder で選択表示する (編集は好きなエディタで)
    func revealUserDictionary() {
        do {
            let url = try prepareUserDictionaryFile()
            NSWorkspace.shared.activateFileViewerSelecting([url])
        } catch {
            report(String(localized: "提案辞書を作れません: \(error.localizedDescription)"))
        }
    }

    // MARK: - お気に入り

    func saveCurrentAsPreset() {
        guard !isApplying, let o = overlay.overlay else { return }
        do { try presets.add(name: nil, overlay: o, settings: overlay.settings) }
        catch { errorMessage = error.localizedDescription }
    }

    func applyPreset(_ preset: Preset) {
        guard !isApplying else { return }
        overlay.restore(overlay: preset.overlay, settings: preset.settings)
        lastPresetStore.id = preset.id
    }

    /// 直前に使ったお気に入り (削除済み・未記録なら nil)
    var lastAppliedPreset: Preset? {
        guard let id = lastPresetStore.id else { return nil }
        return presets.presets.first { $0.id == id }
    }

    /// 履歴の行を現在の入力に戻す (旧形式は不可)。フォルダがまだあればリストに足す。
    /// ブックマークが無い/解決できずサンドボックス下でアクセスできないフォルダは
    /// FolderSelection.add で黙って弾かれるので、追加できたか確認してから初めてオーバーレイを戻す。
    func restore(from task: IconTask) {
        guard !isApplying else { return }
        guard task.overlay.canReapply else { return }
        let url = folderURL(for: task)
        folders.add([url])
        guard folders.folders.contains(url.standardizedFileURL) else {
            // 追加できなかった URL のために開いたスコープは、リストに無いので即座に閉じる
            releaseScopes(keeping: folders.folders)
            let name = url.lastPathComponent
            errorMessage = String(localized: "フォルダーを開けません: \(name)。フォルダーを追加し直してください。")
            return
        }
        overlay.restore(overlay: task.overlay, settings: task.settings)
    }

    /// 履歴の行が指すフォルダ。App Sandbox 下では再起動後に素のパスでは書き込めないので、
    /// ブックマークがあればそちらを優先する。
    private func folderURL(for task: IconTask) -> URL {
        guard !task.bookmarkData.isEmpty,
              let url = try? BookmarkManager.resolveBookmark(task.bookmarkData) else {
            return URL(fileURLWithPath: task.folderPath)
        }
        // リストに残っている間ずっとアクセス権が要るので開いたままにする。
        // 同じフォルダを何度も再適用しても二重に開かない (閉じる回数と釣り合わなくなるため)
        let key = url.standardizedFileURL
        if scopedURLs[key] == nil, url.startAccessingSecurityScopedResource() {
            scopedURLs[key] = url
        }
        return url
    }

    /// リストに無くなったフォルダのセキュリティスコープを閉じる
    private func releaseScopes(keeping list: [URL]) {
        let keep = Set(list)
        for (key, url) in scopedURLs where !keep.contains(key) {
            url.stopAccessingSecurityScopedResource()
            scopedURLs.removeValue(forKey: key)
        }
    }

    deinit {
        contentScanTask?.cancel()
        for url in scopedURLs.values { url.stopAccessingSecurityScopedResource() }
    }

    func removePreset(_ preset: Preset) {
        guard !isApplying else { return }
        do { try presets.remove(preset) } catch { errorMessage = error.localizedDescription }
        reapAssets()
    }

    func renamePreset(_ preset: Preset, to name: String) {
        guard !isApplying else { return }
        do { try presets.rename(preset, to: name) } catch { errorMessage = error.localizedDescription }
    }

    static let packType = UTType(exportedAs: "com.example.folderart.pack", conformingTo: .json)
    static let exportPackNotification = Notification.Name("FolderArt.exportPack")
    static let importPackNotification = Notification.Name("FolderArt.importPack")

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
    }

    /// お気に入り全部を 1 ファイルに書き出す (NSSavePanel)
    func exportPack() {
        exportPack(presets: presets.presets)
    }

    /// 選んだお気に入りだけを 1 ファイルに書き出す (NSSavePanel)。空なら理由を伝えて戻る
    func exportPack(presets selected: [Preset]) {
        guard !isApplying else { return }
        // ファイルメニューからは常に選べるので、帯の「…」と違って黙って戻らず理由を伝える
        guard !selected.isEmpty else {
            errorMessage = String(localized: "書き出せるお気に入りがありません。")
            return
        }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [Self.packType]
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyyMMdd"
        panel.nameFieldStringValue = String(localized: "FolderArt-お気に入り-\(formatter.string(from: Date())).folderartpack")
        panel.prompt = String(localized: "書き出す")
        if panel.runModal() == .OK, let url = panel.url { exportPack(to: url, presets: selected) }
    }

    /// presets を省略すれば全件。空なら書かずに理由を伝える (NSSavePanel を通らない経路も同じ判定を通す)
    func exportPack(to url: URL, presets selected: [Preset]? = nil) {
        guard !isApplying else { return }
        let toWrite = selected ?? presets.presets
        guard !toWrite.isEmpty else {
            errorMessage = String(localized: "書き出せるお気に入りがありません。")
            return
        }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        do {
            let data = try PackWriter.write(toWrite, assets: assets, appVersion: appVersion)
            try data.write(to: url, options: .atomic)
        } catch {
            errorMessage = String(localized: "パックを書き出せませんでした: \(error.localizedDescription)")
        }
    }

    /// パックを選んで読み込む (NSOpenPanel)
    func importPackWithPanel() {
        guard !isApplying else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [Self.packType, .json]
        panel.prompt = String(localized: "読み込む")
        if panel.runModal() == .OK, let url = panel.url { Task { await importPack(url: url) } }
    }

    /// パックを読み込んでお気に入りに追加し、結果をアラートで伝える。
    /// ファイルの読み込みと検証 (JSON の復号・画像の検査) は 100 MB 級でも UI を止めないようメインの外で行い、
    /// お気に入りへの追加 (ストアの更新) だけメインで行う
    func importPack(url: URL) async {
        // 同時に複数のパックを読まない (1 つ 100 MB まで読むので、重なるとメモリを食う)
        guard !isApplying, !isImportingPack else { return }
        isImportingPack = true
        defer { isImportingPack = false }
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        let read = await Task.detached(priority: .userInitiated) { Self.readPack(at: url) }.value
        do {
            let pack = try read.get()
            let summary = try PresetImporter.importPack(pack, into: presets, assets: assets)
            errorMessage = summary.skippedIdentical == 0
                ? String(localized: "\(summary.added) 件のお気に入りを追加しました。")
                : String(localized: "\(summary.added) 件のお気に入りを追加しました (\(summary.skippedIdentical) 件は同じものがあるため省略)。")
        } catch let error as PackError {
            errorMessage = error.errorDescription
        } catch {
            errorMessage = String(localized: "パックを読み込めません: \(error.localizedDescription)")
        }
    }

    /// 上限までしか読まない (巨大なファイルや、サイズの分からないファイルを丸ごとメモリに載せない)。
    /// 短い read が返る経路 (ファイルプロバイダなど) もあるので、EOF か上限を超えるまで読み続ける
    nonisolated private static func readPack(at url: URL) -> Result<Pack, Error> {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            defer { try? handle.close() }
            var data = Data()
            while data.count <= PackReader.maxFileBytes, let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                data.append(chunk)
            }
            guard data.count <= PackReader.maxFileBytes else { throw PackError.fileTooLarge }
            return .success(try PackReader.read(data, symbolCatalog: SymbolCatalog.shared))
        } catch {
            return .failure(error)
        }
    }

    // MARK: - 画像の回収

    /// 履歴・お気に入り・現在の選択のどれからも参照されない PNG を消す。
    /// どちらかのストアが読めていない (空で始まっている) ときは、参照中の画像を消さないよう何もしない。
    /// 適用中は履歴/お気に入りへの書き込みと競合しうるので何もしない (apply() 完了後に呼び直される)。
    func reapAssets() {
        guard !isApplying, history.loadError == nil, presets.loadError == nil else { return }
        var keep = history.referencedAssetIDs.union(presets.referencedAssetIDs)
        if let id = overlay.imageAssetID { keep.insert(id) }
        _ = try? assets.reap(keeping: keep)
    }

    // MARK: - Quick Action (Finder サービス)

    /// URL 群のうち、実在するディレクトリだけを standardized で返す (ファイル・欠落は除外)。
    /// 純関数で AppModel の状態に触れないため nonisolated (QuickActionProvider の nonisolated な
    /// static コンテキストから同期で呼べるようにする)
    nonisolated static func directories(from urls: [URL]) -> [URL] {
        urls.compactMap { url in
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else { return nil }
            return url.standardizedFileURL
        }
    }

    /// フォルダーをリストに読み込んでアプリを前面化する (サービス「FolderArt で開く」)
    func openFolders(_ urls: [URL]) {
        let dirs = Self.directories(from: urls)
        guard !dirs.isEmpty else { return }
        folders.add(dirs)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Quick Action の適用結果。呼び出し側 (QuickActionProvider) が前面化とアラートを判断する。
    enum QuickApplyResult: Equatable {
        case applied         // 1 つ以上のフォルダーに適用できた (静かに終了してよい)
        case noPreset        // 直前のお気に入りが無い/解決できない/対象フォルダーが無い
        case failed(String)  // お気に入りはあるが、描画に失敗 or 全フォルダーで失敗 (メッセージ付き)
    }

    /// 直前のお気に入りを、UI 状態に触れず指定フォルダーへ静かに適用する。
    func applyLastPreset(to urls: [URL]) async -> QuickApplyResult {
        let dirs = Self.directories(from: urls)
        guard let preset = lastAppliedPreset, !dirs.isEmpty else { return .noPreset }
        guard let image = OverlayRenderer.render(preset.overlay, settings: preset.settings,
                                                 side: IconComposer.iconSize.width, assets: assets) else {
            return .failed(String(localized: "お気に入りの絵柄を作れませんでした。"))
        }
        let started = dirs.filter { $0.startAccessingSecurityScopedResource() }
        defer { for u in started { u.stopAccessingSecurityScopedResource() } }
        let outcome = await coordinator.apply(overlayImage: image, overlay: preset.overlay,
                                              settings: preset.settings, to: dirs)
        reapAssets()
        if outcome.succeeded.isEmpty {
            return .failed(outcome.summary ?? String(localized: "フォルダーにアイコンを適用できませんでした。"))
        }
        return .applied
    }

    /// FolderArt が付けたアイコンだけを元に戻す (サービス「アイコンを元に戻す」)。
    /// 戻り値は「エラーが 1 件も無かったか」(呼び出し側の QuickActionProvider が静かに終了してよいか判断するため)
    @discardableResult
    func resetIcons(at urls: [URL]) -> Bool {
        var succeeded = true
        for url in Self.directories(from: urls) where hasHistory(url) {
            let started = url.startAccessingSecurityScopedResource()
            defer { if started { url.stopAccessingSecurityScopedResource() } }
            do { try coordinator.reset(folder: url) }
            catch { errorMessage = error.localizedDescription; succeeded = false }
        }
        reapAssets()
        return succeeded
    }
}
