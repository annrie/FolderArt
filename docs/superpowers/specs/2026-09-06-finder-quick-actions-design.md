# FolderArt 第5段階 設計 — Finder クイックアクション (Services)

**日付:** 2026-09-06
**対象バージョン:** 1.6.0 / ビルド 9
**前段階:** 1.5.0 (第4段階、PR #5 で `develop` 済み)

## 1. 目的 / Goal

Finder の右クリック (コンテキストメニュー) から、アプリ画面を開かずにフォルダーへ操作できるようにする。macOS の `NSServices` (「クイックアクション」/「サービス」) を本体アプリ自身が提供する方式を採る。別の App Extension ターゲットや App Group は作らない。

Let users act on folders from Finder's right-click menu without opening the app's window, by having the main app vend `NSServices` (shown under Quick Actions / Services). No separate app-extension target and no App Group.

## 2. 方式の決定と背景 / Approach

検討した 3 方式のうち **Services (NSServices)** を採用 (ユーザー決定 2026-09-06)。

| 方式 | 長所 | 短所 | 判定 |
|---|---|---|---|
| Services (NSServices) | 別ターゲット不要・自動登録・署名要件が増えない・既存コードをそのまま再利用 | 項目は Info.plist の静的宣言のみ (お気に入りごとの動的メニュー不可)、メニューは「クイックアクション/サービス」配下 | **採用** |
| Finder Sync 拡張 | トップ階層メニュー・バッジ可 | 署名必須の別 Extension・App Group・システム設定での有効化。未署名 zip 配布と相性が悪い | 見送り |
| ランチャーのみ | 最小 | 既存のドラッグ&ドロップと大差なし | 不十分 |

**なぜ Services が本アプリに合うか:** 本体はサンドボックス (`app-sandbox` + `files.user-selected.read-write` + `files.bookmarks.app-scope`) で、アイコン適用は `NSWorkspace.setIcon(_:forFile:)`、フォルダーアクセスは security-scoped bookmark。Services は本体プロセスで動くため、`AppModel` / `FolderIconManager` / レンダリング一式をそのまま使える。Finder Sync のように署名済みの別プラグインを load させる必要がないので、現在の配布形態 (未署名 zip、右クリック→開く) を変えずに済む。

## 3. 提供する 3 つのサービス / The three services

Info.plist の `NSServices` 配列に固定名で 3 つ宣言する。すべて `NSSendFileTypes` にフォルダー (`public.folder`) を受け取る。`NSRequiredContext` で複数フォルダー選択にも対応する。

1. **FolderArt で開く / Open in FolderArt**
   - 受け取ったフォルダー URL を本体リストに追加し、アプリを前面化する。
   - 既存の「フォルダーをリストに追加」経路 (ドラッグ&ドロップ相当) に流すだけ。常に安全。
2. **直前のお気に入りを適用 / Apply Last Preset**
   - 記録済みの「最後に適用したお気に入り」を、ウィンドウを出さずに静かに適用する。
   - 成功の合図は Finder のアイコンが変わること自体 (通知は出さない)。
   - お気に入りをまだ一度も適用していない場合は、アプリを前面化して優しく知らせる (エラー扱い)。
3. **アイコンを元に戻す / Reset Icon**
   - FolderArt が付けたアイコンを、バックアップがあるフォルダーについて元に戻す。
   - FolderArt が触っていない (バックアップの無い) フォルダーには何もしない。

### 3.1 Info.plist の宣言 (各サービスの形)

```xml
<key>NSServices</key>
<array>
  <dict>
    <key>NSMenuItem</key>
    <dict><key>default</key><string>FolderArt で開く</string></dict>
    <key>NSMessage</key><string>openFoldersInFolderArt</string>
    <key>NSPortName</key><string>FolderArt</string>
    <key>NSSendFileTypes</key><array><string>public.folder</string></array>
    <key>NSRequiredContext</key><dict/>
  </dict>
  <!-- applyLastPreset (直前のお気に入りを適用) / resetIcon (アイコンを元に戻す) も同型 -->
</array>
```

- メニュー表示名 (`NSMenuItem` > `default`) は英語ロケール既定を英語、`InfoPlist.xcstrings` で 8 言語化する (サービス名のローカライズは `InfoPlist.strings`/String Catalog 経由)。
- `NSMessage` はサービス提供オブジェクトのメソッド名。3 つ: `openFoldersInFolderArt`, `applyLastPreset`, `resetIcon`。
- 受け取り型は `public.folder` に限定 (ファイルには出さない)。

## 4. サービス提供オブジェクト / Service provider

新規 `FolderArt/Services/QuickActionService.swift` (仮) に `NSObject` サブクラスを置き、`AppDelegate`/App 起動時に `NSApp.servicesProvider = provider` を設定、`NSUpdateDynamicServices()` を必要に応じ呼ぶ。

各サービスメソッドの署名 (AppKit の Services 規約):

```swift
@objc func openFoldersInFolderArt(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?)
@objc func applyLastPreset(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?)
@objc func resetIcon(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString>?)
```

- pboard から `NSURL` 配列 (`readObjects(forClasses: [NSURL.self])`, `options: filterToFileURLs`) を取り出し、ディレクトリだけに絞る。
- 取り出した URL を `AppModel` の該当処理へ委譲する (main actor へ)。ロジックの本体は `AppModel` 側に置き、`QuickActionService` は「pboard → [URL] 変換 + AppModel 呼び出し」の薄い層にする (テスト容易性のため、URL→フォルダー変換と last-used 解決・reset 判定は純粋関数/AppModel メソッドとして切り出す)。

### 4.1 AppModel への追加

- `func openFolders(_ urls: [URL])` — リストに追加して前面化 (既存の追加経路を使う)。
- `func applyLastPreset(to urls: [URL]) -> Bool` — last-used preset を解決し、無ければ false。あれば各フォルダーへ適用 (既存の一括適用経路を使う)。
- `func resetIcons(at urls: [URL])` — バックアップのあるものだけ戻す (既存の reset 経路を使う)。
- 適用・reset は既存の `ApplyCoordinator` / `FolderIconManager` を通す。security-scoped アクセスは Services で渡った URL に対して開始/終了する (`startAccessingSecurityScopedResource`)。

## 5. 「最後に適用したお気に入り」の永続化 / Last-used preset

- 新しい状態として、最後に適用したお気に入りの `id` (UUID) を保存する。
- 保存先: `PresetStore` に薄く持たせる (`lastAppliedPresetID: UUID?` を JSON に保存) か、専用の小さな defaults。**採用: `PresetStore` に持たせて既存の保存機構を再利用**する (お気に入りと同じライフサイクル)。
- 更新タイミング: お気に入り由来でアイコンを適用したとき (単体 `applyPreset` 経由の適用確定時、および一括適用でお気に入りを使ったとき)。オーバーレイを直接編集しただけでは更新しない。
- 解決: `applyLastPreset` 時に id からお気に入りを引く。id はあるが対応するお気に入りが削除済みなら「未記録」と同じ扱い (前面化して知らせる)。

## 6. 起動とフォアグラウンド制御 / Launch & quiet terminate

「直前のお気に入りを適用」「アイコンを元に戻す」の静かな 2 つについて:

- **アプリが既に起動しているとき** — その場で裏で処理。ウィンドウ状態は変えない。起動も終了もしない。
- **アプリが閉じているとき** — macOS が処理のために起動する。このとき:
  - メインウィンドウを出さない (サービス起動を検知し、ウィンドウ表示を抑止する)。
  - アイコン書き込み (非同期) の**完了を待ってから**、自分で終了する (静かに終了する案、ユーザー承認済み)。
  - 「サービスのためだけに起動されたか」の判定: 起動直後にサービスメソッドが呼ばれたか、かつユーザーがウィンドウを開いていないかで判断する。実装は「アプリ起動フラグ + サービス呼び出しで確定 → 完了後 `NSApp.terminate` 相当」。
- **FolderArt で開く** — 通常どおり前面化してウィンドウを表示 (静かに終了はしない)。
- 競合防止: 静かな適用の途中でユーザーがウィンドウを開いた等の場合は終了しない (フラグで判定)。

## 7. サンドボックス・権限・配布 / Sandbox, entitlements, distribution

- entitlements は現状維持を基本とする (`app-sandbox`, `files.user-selected.read-write`, `files.bookmarks.app-scope`)。Services で渡ったフォルダー URL にはサンドボックスがアクセス権を付与する。
- **唯一の技術的リスク:** サービス経由で受け取ったフォルダーに `NSWorkspace.setIcon` の**書き込み**が権限内で通るか。**実装の最初のタスクで実機確認する**。通らない場合のフォールバック: 静かな適用/戻すを諦め、代わりに「FolderArt で開く」に倒す (フォルダーを読み込んで、アプリ側で従来どおり user-selected として扱う)。この分岐は spec の受け入れ条件に含める。
- 配布: Services を Launch Services に確実に登録させるため、本体を `/Applications` または `~/アプリケーション` に置いて 1 度起動する手順を README に明記する。必要なら `lsregister` / `NSUpdateDynamicServices()` の案内も。Finder Sync と違い署名必須の別 Extension は無いので、現在の未署名 zip 配布のままでよい。
- 右クリックに出ない場合の案内 (システム設定 > キーボード > キーボードショートカット > サービス、または「拡張機能」でのチェック) を README に書く。

## 8. エラー処理 / Errors

- アクセス不可・書き込み失敗・last-used preset 未記録 (または削除済み) の各ケースで、アプリを前面化し既存の `errorMessage` アラートで知らせる。
- 文言はすべて `strings.json` に追加し 8 言語化 (例: 「まだお気に入りを適用していません」「フォルダーにアクセスできません: %@」)。
- 静かな処理の成功時は無音 (Finder のアイコン変化が合図)。

## 9. テスト / Testing

- ユニット: pboard→[URL] 変換 (ディレクトリのみ抽出、ファイル除外、複数選択)、last-used preset の解決 (記録あり/なし/削除済み)、reset 判定 (バックアップあり/なし)、`PresetStore` の `lastAppliedPresetID` 永続化と後方互換 (旧 JSON に欄が無ければ nil)。
- 実機目視 (コントローラー): 右クリックにクイックアクション 3 項目が出る、「開く」で読み込み前面化、「適用」で Finder のアイコンが変わりウィンドウが出ない・アプリが残らない、「戻す」で元に戻る、未記録時のアラート、複数フォルダー選択。
- 既存テストは全通過を維持。文言は `--check` と `check-compiled.sh` で missing 0。

## 10. やらないこと / Out of scope

- Finder Sync のトップ階層メニュー・バッジ。
- お気に入りを個別に並べる動的メニュー (NSServices の静的宣言では不可)。
- 複数解像度アイコン、提案辞書の多言語キー、提案精度改善などは第6弾以降。
- notarization / 署名の導入 (現状の配布形態を維持)。

## 11. 受け入れ条件 / Acceptance

1. サービス経由でフォルダーにアイコンを書き込めることを実機で確認済み (または、通らない場合のフォールバックが実装されている)。
2. 右クリック > クイックアクションに 3 項目が表示され、それぞれ仕様どおり動く。
3. 静かな 2 項目は、閉じた状態から実行してもウィンドウを出さず、処理後にアプリが残らない。
4. 「最後に適用したお気に入り」が永続化され、旧データと後方互換 (欄が無ければ nil)。
5. 新規文言は 8 言語、`--check` / `check-compiled.sh` ともに missing 0。全テスト通過。
6. README に有効化・置き場所・トラブルシュートを日英併記で追記。バージョン 1.6.0 / ビルド 9。
