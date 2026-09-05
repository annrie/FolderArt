# FolderArt 第3段階 実装計画: フォント・太さの UI、多言語化、フォルダの中身からの生成

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 文字のフォントと記号・文字の太さを選べ、8 言語 (ja / en / de / es / fr / ko / pt-BR / zh-Hant) で使え、フォルダの中身 (ファイルの種類と代表画像) からも提案が出る FolderArt 1.4.0 を作る。

**Architecture:** フォントは `FontCatalog` (厳選 8 家族 + `NSFontDescriptor` による家族 + 太さの解決) が `OverlayRenderer` と `ControlsView` に供給する。多言語化は `scripts/localization/strings.json` (キー → 8 言語) から生成した `Localizable.xcstrings` (sourceLanguage en、キーは日本語リテラル) と、`LanguageSetting` (UserDefaults の `AppleLanguages` を書いて再起動を促す) の 2 部品。中身からの提案は `ContentScanner` (直下を逐次列挙して種類を数え、代表画像のサムネイル PNG を作る純関数) → `SuggestionEngine.suggest(for:presets:content:)` (名前の候補を優先し空枠を埋め、画像チップを末尾に足す) → `AppModel` (対象フォルダが変わったときだけ generation 付きで非同期走査) の流れ。

**Tech Stack:** Swift 5.9, SwiftUI + AppKit, macOS 13.0+, XcodeGen 2.46 (project.yml が正), XCTest, String Catalog (`.xcstrings`)、Python 3 (macOS 同梱、カタログ生成スクリプトのみ)。

**Spec:** `docs/superpowers/specs/2026-09-05-fonts-i18n-contents-design.md`

## Global Constraints

- deploymentTarget macOS 13.0、SWIFT_VERSION 5.9。macOS 14 以降専用 API は使わない (`@Observable` 不可、`onChange(of:initial:)` 不可、`onChange(of:) { value in }` の 1 引数形を使う)。
- 新しいファイルを追加したら `xcodegen generate` を実行し、`FolderArt.xcodeproj/project.pbxproj` の差分もコミットに含める。`FolderArt/Resources/*.json` / `*.txt` / `*.xcstrings` は XcodeGen が自動でリソースに入れる。`scripts/` 配下は `project.yml` の `sources` に含まれないのでビルドには入らない。
- テスト実行コマンド (以後「テスト実行」):
  ```bash
  xcodebuild test -project FolderArt.xcodeproj -scheme FolderArt -destination 'platform=macOS' 2>&1 | grep -E "warning:|error:| failed|Executed [0-9]+ tests|TEST (SUCCEEDED|FAILED)" | grep -v "ld: warning"
  ```
  1 クラスだけ走らせるときは `-only-testing:FolderArtTests/<ClassName>` を足す。プロジェクト由来の `warning:` は 0 件を保つ (`appintentsmetadataprocessor` の `Metadata extraction skipped` と `ld: warning` は環境由来で無視)。
- テストはアプリ自身をホストとしてサンドボックス内で走る (`BookmarkManager.isSandboxed == true`)。一時ファイルは `FileManager.default.temporaryDirectory` 配下に作れば読み書きできる。**リポジトリのソースツリー (`#filePath` 経由) はサンドボックスから読めない前提で書く** (カタログの検証はビルド済みバンドルの `.lproj` を見る)。
- UI 文言はすべて `Text("…")` (自動で `LocalizedStringKey`) か `String(localized:)`。`String` 型を経由した文言 (三項演算子、`String` のプロパティ、`String(format:)`) を `Text` に渡さない。**新しい文言を足したら `scripts/localization/strings.json` に 8 言語分の行を足し、`python3 scripts/localization/build-xcstrings.py` で `Localizable.xcstrings` を作り直してコミットに含める。** `python3 scripts/localization/build-xcstrings.py --check` が「missing: 0」であること。
- 文言のキーは Swift の補間から抽出される形: `Int` は `%lld`、`String` は `%@`、リテラルの `%` は `%%`。単複の variation は値を `one||other` の形で書く (数が 1 つだけの文言に限る。ja / ko / zh-Hant は 1 形)。
- 新しい依存パッケージは追加しない。SF Symbols の画像を同梱しない。
- コミットメッセージは既存の流儀 (`feat: ✨ …`, `fix: 🐛 …`, `refactor: ♻️ …`, `test: ✅ …`, `docs: 📝 …`, `chore: 🔧 …` + 日本語) に合わせ、末尾に次を付ける:
  ```
  Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
  Claude-Session: https://claude.ai/code/session_019Vg5PGSSK7UQZw2QYFBqph
  ```
- ブランチは `feature/fonts-i18n-contents` (作成済み、`develop` = `main` = v1.3.0 から分岐)。main / develop には直接コミットしない。
- 既存の 192 テストは維持する (2026-09-05 のベースライン: `Executed 192 tests, with 0 failures`)。

## File Structure

```
FolderArt/
├── AppModel.swift                     変更: 中身の走査 (generation、cancel、scanner 注入)、.image の採用、既定ファイル名の文言
├── FolderArtApp.swift                 変更: 「表示 > 言語」メニュー、LanguageSetting、defaultSize 780
├── ContentView.swift                  変更: showsFont / showsWeight、再起動アラート、minHeight 780
├── Models/
│   ├── CodableColor.swift             変更: FontWeightValue.displayName
│   └── Suggestion.swift               変更: Kind.image(RepresentativeImage)
├── Services/
│   ├── FontCatalog.swift              新規: FontChoice、厳選 8 家族、家族 + 太さの解決
│   ├── ContentScanner.swift           新規: ContentKind / RepresentativeImage / ContentSummary / ContentScanner
│   ├── AppLanguage.swift              新規: AppLanguage / LanguageSetting
│   ├── OverlayRenderer.swift          変更: makeFont → FontCatalog、render(image:side:) の公開
│   ├── SuggestionEngine.swift         変更: suggest(for:presets:content:)
│   ├── SuggestionDictionary.swift     変更: entry(forKey:)
│   ├── ApplyCoordinator.swift         変更: 文言を String(localized:) に
│   └── BookmarkManager.swift          変更: 文言を String(localized:) に
├── Views/
│   ├── ControlsView.swift             変更: フォント・太さの 2 行、三項演算子の修正
│   ├── SuggestionStripView.swift      変更: 横スクロール、ラベル幅、.image チップ
│   └── DropZoneView.swift             変更: buttonLabel を LocalizedStringKey に
└── Resources/
    ├── Localizable.xcstrings          新規 (生成物): 8 言語
    ├── InfoPlist.xcstrings            新規 (生成物): 書類の種類名
    └── suggestions.json               変更: presentation / spreadsheet の項目
scripts/localization/
├── strings.json                       新規: キー → [ja, en, de, es, fr, ko, pt-BR, zh-Hant]
├── infoplist.json                     新規: InfoPlist 用
└── build-xcstrings.py                 新規: 生成 (--check でソースとの突き合わせ)
FolderArtTests/
├── LocalizationTests.swift            新規
├── FontCatalogTests.swift             新規
├── ContentScannerTests.swift          新規
├── LanguageSettingTests.swift         新規
├── OverlayRendererTests.swift         変更: 家族指定の文字
├── SuggestionDictionaryTests.swift    変更: entry(forKey:)
├── SuggestionEngineTests.swift        変更: content の合流
├── AppModelTests.swift                変更: 走査の generation / cancel / 注入
└── ApplyCoordinatorTests.swift        変更: contains を String(localized:) に
project.yml                            変更: 1.4.0 / ビルド 7、developmentLanguage、LOCALIZATION_PREFERS_STRING_CATALOGS
README.md                              変更: 機能一覧、構成、画像
docs/images/main.png                   変更: 1.4.0 の画面
```

---

### Task 1: 未ローカライズ箇所の修正 (String 型を経由する文言)

**Files:**
- Modify: `FolderArt/Services/BookmarkManager.swift:3-15`
- Modify: `FolderArt/Services/ApplyCoordinator.swift:16-17,128`
- Modify: `FolderArt/Views/DropZoneView.swift:37-39`
- Modify: `FolderArt/Views/ControlsView.swift:46-47`
- Modify: `FolderArt/AppModel.swift:344`
- Modify: `FolderArtTests/ApplyCoordinatorTests.swift:290`

**Interfaces:**
- Consumes: なし
- Produces: 文言のキーが次のとおりになる (Task 2 の `strings.json` がこのキーを持つ): `ブックマーク作成失敗: %@` / `ブックマーク解決失敗: %@` / `ブックマークが古くなっています` / `・%@: %@` / `%@ / 巻き戻し失敗: %@` / `FolderArt-お気に入り-%@.folderartpack`。`DropZoneView.buttonLabel: LocalizedStringKey`。

- [ ] **Step 1: BookmarkManager のエラー文を `String(localized:)` にする**

`FolderArt/Services/BookmarkManager.swift` の `errorDescription` を次に置き換える:

```swift
    var errorDescription: String? {
        switch self {
        case .creationFailed(let msg):   return String(localized: "ブックマーク作成失敗: \(msg)")
        case .resolutionFailed(let msg): return String(localized: "ブックマーク解決失敗: \(msg)")
        case .stale:                     return String(localized: "ブックマークが古くなっています")
        }
    }
```

- [ ] **Step 2: ApplyCoordinator の 2 箇所**

`FolderArt/Services/ApplyCoordinator.swift` の `ApplyOutcome.summary`:

```swift
    var summary: String? {
        guard !failed.isEmpty else { return nil }
        let lines = failed.map { String(localized: "・\($0.folder.lastPathComponent): \($0.reason)") }.joined(separator: "\n")
        return String(localized: "\(succeeded.count) 件成功、\(failed.count) 件失敗") + "\n\n" + lines
    }
```

同ファイル 128 行目付近の巻き戻し失敗の連結 (`reason += " / 巻き戻し失敗: …"`) を次に置き換える:

```swift
                var reason = error.localizedDescription
                if rollbackFailed {
                    reason = String(localized: "\(reason) / 巻き戻し失敗: \(FolderIconError.resetFailed(folder).localizedDescription)")
                }
                failed.append(ApplyFailure(folder: folder, reason: reason))
```

- [ ] **Step 3: DropZoneView の buttonLabel**

`FolderArt/Views/DropZoneView.swift`:

```swift
    private var buttonLabel: LocalizedStringKey {
        displayURL == nil ? "画像を選択..." : "変更..."
    }
```

(`Button(buttonLabel, action:)` はそのまま。`LocalizedStringKey` を受ける初期化子に切り替わる)

- [ ] **Step 4: ControlsView の三項演算子**

`FolderArt/Views/ControlsView.swift` の色の行にある `Text(showsTint ? "記号と文字に適用" : "記号と文字にのみ適用されます")` を次に置き換える (Task 4 でこの行の周りを書き直すが、先に文言だけ直しておく):

```swift
                (showsTint ? Text("記号と文字に適用") : Text("記号と文字にのみ適用されます"))
                    .font(.caption).foregroundColor(.secondary)
```

- [ ] **Step 5: 書き出しの既定ファイル名**

`FolderArt/AppModel.swift` の `exportPack()` 内:

```swift
        panel.nameFieldStringValue = String(localized: "FolderArt-お気に入り-\(formatter.string(from: Date())).folderartpack")
```

- [ ] **Step 6: テストの文字列照合を言語に依存しない形にする**

`FolderArtTests/ApplyCoordinatorTests.swift` の `XCTAssertTrue(outcome.failed.allSatisfy { $0.reason.contains("履歴の保存に失敗") })` を次に置き換える:

```swift
        let prefix = String(localized: "履歴の保存に失敗しました: \("")")
        XCTAssertTrue(outcome.failed.allSatisfy { $0.reason.hasPrefix(prefix) }, outcome.failed.map(\.reason).joined(separator: " | "))
```

- [ ] **Step 7: テスト実行**

Run: テスト実行 (全体)
Expected: `Executed 192 tests, with 0 failures`、プロジェクト由来の警告 0

- [ ] **Step 8: コミット**

```bash
git add FolderArt/Services/BookmarkManager.swift FolderArt/Services/ApplyCoordinator.swift FolderArt/Views/DropZoneView.swift FolderArt/Views/ControlsView.swift FolderArt/AppModel.swift FolderArtTests/ApplyCoordinatorTests.swift
git commit -m "fix: 🐛 String 型を経由して訳が効かなかった文言を String(localized:) / LocalizedStringKey に揃える"
```

---

### Task 2: 多言語化の土台 (strings.json → Localizable.xcstrings / InfoPlist.xcstrings、検証テスト)

**Files:**
- Create: `scripts/localization/build-xcstrings.py`
- Create: `scripts/localization/strings.json` (内容は次の Task 2 付録)
- Create: `scripts/localization/infoplist.json`
- Create: `FolderArt/Resources/Localizable.xcstrings` (生成物)
- Create: `FolderArt/Resources/InfoPlist.xcstrings` (生成物)
- Modify: `project.yml` (`options.developmentLanguage: en`、`LOCALIZATION_PREFERS_STRING_CATALOGS: YES`)
- Modify: `docs/superpowers/specs/2026-09-05-fonts-i18n-contents-design.md` §4.1 (`SWIFT_EMIT_LOC_STRINGS` は付けない旨)
- Test: `FolderArtTests/LocalizationTests.swift`

**Interfaces:**
- Consumes: Task 1 のキー
- Produces: `FolderArt/Resources/Localizable.xcstrings` (8 言語、全キー `translated`、`extractionState: manual`)、`build-xcstrings.py` (`--check` でソースの日本語リテラルと `strings.json` のキーを突き合わせ、欠けがあれば exit 1)。以後のタスクは `strings.json` に行を足して再生成する。`strings.json` には **この計画の全タスクで使う文言をあらかじめ全部入れる** (後のタスクで文言を増やす手間と漏れを無くす。`--check` は「ソースにあってカタログに無い」だけを失敗にし、「カタログにあってソースに無い」は情報として出す)。

- [ ] **Step 1: 生成スクリプトを書く**

`scripts/localization/build-xcstrings.py`:

```python
#!/usr/bin/env python3
"""strings.json / infoplist.json から String Catalog (.xcstrings) を生成する。

    python3 scripts/localization/build-xcstrings.py          # 生成
    python3 scripts/localization/build-xcstrings.py --check  # ソースの文言との突き合わせ (欠けがあれば exit 1)

strings.json の形: {"キー": ["ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"], ...}
値に "one||other" と書くと単数・複数の variation になる。"\\n" は改行。
キーは Swift の補間から抽出される形 (%lld / %@ / %%) で書く。
sourceLanguage は en (未対応の言語は英語に落ちる)。キーは日本語リテラルのまま。
"""
import json
import os
import re
import sys

LANGS = ["ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"]
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
HERE = os.path.dirname(os.path.abspath(__file__))
TARGETS = [
    ("strings.json", "FolderArt/Resources/Localizable.xcstrings"),
    ("infoplist.json", "FolderArt/Resources/InfoPlist.xcstrings"),
]


def unit(value):
    return {"stringUnit": {"state": "translated", "value": value}}


def localization(value):
    if "||" in value:
        one, other = value.split("||", 1)
        return {"variations": {"plural": {"one": unit(one), "other": unit(other)}}}
    return unit(value)


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        table = json.load(f)
    for key, values in table.items():
        if len(values) != len(LANGS):
            sys.exit(f"{name}: {key!r} has {len(values)} values, expected {len(LANGS)}")
        if values[0] != key:
            sys.exit(f"{name}: ja value must equal the key: {key!r} != {values[0]!r}")
        for lang, v in zip(LANGS, values):
            if "||" in v and lang in ("ja", "ko", "zh-Hant"):
                sys.exit(f"{name}: {key!r}: plural variation is not allowed for {lang}")
    return table


def build(name, dest):
    table = load(name)
    strings = {}
    for key in sorted(table):
        strings[key] = {
            "extractionState": "manual",
            "localizations": {lang: localization(v) for lang, v in zip(LANGS, table[key])},
        }
    doc = {"sourceLanguage": "en", "strings": strings, "version": "1.0"}
    path = os.path.join(ROOT, dest)
    with open(path, "w", encoding="utf-8") as f:
        json.dump(doc, f, ensure_ascii=False, indent=2, sort_keys=True)
        f.write("\n")
    print(f"wrote {dest} ({len(strings)} keys)")


JAPANESE = re.compile(r"[぀-ヿ一-鿿]")
LITERAL = re.compile(r'"((?:[^"\\]|\\.)*)"')
SPECIFIER = re.compile(r"%(?:\d+\$)?(?:lld|@|d|%)")


def normalize_key(key):
    return SPECIFIER.sub("%", key)


def normalize_literal(lit):
    # \(expr) → %、\n → 改行、\" → "、\\ → \
    out, i = [], 0
    while i < len(lit):
        if lit.startswith("\\(", i):
            depth, j = 1, i + 2
            while j < len(lit) and depth:
                depth += {"(": 1, ")": -1}.get(lit[j], 0)
                j += 1
            out.append("%")
            i = j
        elif lit.startswith("\\n", i):
            out.append("\n"); i += 2
        elif lit.startswith('\\"', i):
            out.append('"'); i += 2
        elif lit.startswith("\\\\", i):
            out.append("\\"); i += 2
        else:
            out.append(lit[i]); i += 1
    # リテラル中の "%" はそのまま残す (キー側の "%%" と "%lld" が両方 "%" に正規化されるので、"上\\(n)%" は "上%%" になり "上%lld%%" と一致する)
    return "".join(out)


def source_literals():
    """FolderArt/ 配下の Swift から、日本語を含む文字列リテラル (コメント行を除く) を集める"""
    found = {}
    for dirpath, _, filenames in os.walk(os.path.join(ROOT, "FolderArt")):
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            path = os.path.join(dirpath, fn)
            with open(path, encoding="utf-8") as f:
                for lineno, line in enumerate(f, 1):
                    code = line.strip()
                    if code.startswith("//"):
                        continue
                    code = re.split(r"\s//", line)[0]
                    for m in LITERAL.finditer(code):
                        lit = m.group(1)
                        if JAPANESE.search(lit):
                            found.setdefault(normalize_literal(lit), []).append(f"{os.path.relpath(path, ROOT)}:{lineno}")
    return found


def check():
    table = load("strings.json")
    keys = {normalize_key(k) for k in table}
    literals = source_literals()
    missing = {lit: where for lit, where in literals.items() if lit not in keys}
    used = {normalize_key(k) for k in table if normalize_key(k) in literals}
    unused = sorted(k for k in table if normalize_key(k) not in literals)
    for lit, where in sorted(missing.items()):
        print(f"missing: {lit!r}  ({', '.join(where)})")
    for k in unused:
        print(f"unused (info): {k!r}")
    print(f"missing: {len(missing)}, unused: {len(unused)}, used: {len(used)}")
    sys.exit(1 if missing else 0)


if __name__ == "__main__":
    if "--check" in sys.argv[1:]:
        check()
    else:
        for name, dest in TARGETS:
            build(name, dest)
```

- [ ] **Step 2: infoplist.json を書く**

`scripts/localization/infoplist.json`:

```json
{
  "FolderArt Preset Pack": ["FolderArt Preset Pack", "FolderArt Preset Pack", "FolderArt-Vorlagenpaket", "Paquete de favoritos de FolderArt", "Pack de favoris FolderArt", "FolderArt 즐겨찾기 팩", "Pacote de favoritos do FolderArt", "FolderArt 收藏套件"]
}
```

(InfoPlist はキーが英語なので、`ja` の値もキーと同じにしておく。`load()` の「ja の値 = キー」検証はこの表にも効く。日本語表記は `Finder` の「情報を見る」にしか出ないので英語のままで良い)

- [ ] **Step 3: strings.json を書く**

`scripts/localization/strings.json` を **Task 2 付録** の内容で作る (全文をそのまま保存する。キーの順は問わない。生成時にソートされる)。

- [ ] **Step 4: 生成して --check を通す**

```bash
python3 scripts/localization/build-xcstrings.py
python3 scripts/localization/build-xcstrings.py --check
```

Expected: `wrote FolderArt/Resources/Localizable.xcstrings (N keys)`、`wrote FolderArt/Resources/InfoPlist.xcstrings (1 keys)`、`--check` の最終行が `missing: 0, unused: M, used: K` (M は後のタスクで使う文言の数。0 でなくてよい)。`missing` が 1 件でもあれば、その文言を `strings.json` に足す (キーの形は §Global Constraints)。

- [ ] **Step 5: project.yml**

`project.yml` の `options:` に `developmentLanguage: en` を足し、`FolderArt` の `settings.base` に `LOCALIZATION_PREFERS_STRING_CATALOGS: YES` を足す:

```yaml
options:
  bundleIdPrefix: com.example
  developmentLanguage: en
  deploymentTarget:
    macOS: "13.0"
  xcodeVersion: "15.0"
  createIntermediateGroups: true
```

```yaml
      base:
        PRODUCT_BUNDLE_IDENTIFIER: com.example.FolderArt
        MARKETING_VERSION: 1.3.0
        CURRENT_PROJECT_VERSION: 6
        SWIFT_VERSION: 5.9
        ENABLE_HARDENED_RUNTIME: YES
        INFOPLIST_FILE: FolderArt/Info.plist
        LOCALIZATION_PREFERS_STRING_CATALOGS: YES
```

`SWIFT_EMIT_LOC_STRINGS` は **付けない** (Xcode がビルド時にカタログへキーを書き足し、生成物と食い違うため。同期は `--check` で行う)。spec §4.1 の「`LOCALIZATION_PREFERS_STRING_CATALOGS: YES` と `SWIFT_EMIT_LOC_STRINGS: YES` を `FolderArt` の settings に足す (Xcode がビルド時にカタログへ新しいキーを同期できるようにする)」を「`LOCALIZATION_PREFERS_STRING_CATALOGS: YES` を `FolderArt` の settings に足す。`SWIFT_EMIT_LOC_STRINGS` は付けない (Xcode がビルド時にカタログへキーを書き足して生成物と食い違うため。ソースとの同期は `scripts/localization/build-xcstrings.py --check` で行う)」に書き換える。

```bash
xcodegen generate
```

- [ ] **Step 6: 検証テストを書く**

`FolderArtTests/LocalizationTests.swift`:

```swift
import XCTest
@testable import FolderArt

/// ビルド済みバンドルの .lproj を見る (サンドボックスからソースツリーは読めない)。
/// どの言語のプロセスで走っても通るよう、比較は英語の .lproj を Bundle として直接開いて行う。
final class LocalizationTests: XCTestCase {
    static let languages = ["ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"]

    /// Localizable.strings と Localizable.stringsdict (単複の variation はこちらに出る) を合わせたキー → 値
    private func table(_ name: String, language: String) -> [String: Any] {
        var merged: [String: Any] = [:]
        for ext in ["strings", "stringsdict"] {
            if let path = Bundle.main.path(forResource: name, ofType: ext, inDirectory: nil, forLocalization: language),
               let dict = NSDictionary(contentsOfFile: path) as? [String: Any] {
                merged.merge(dict) { a, _ in a }
            }
        }
        return merged
    }

    private func bundle(for language: String) throws -> Bundle {
        let path = try XCTUnwrap(Bundle.main.path(forResource: language, ofType: "lproj"), language)
        return try XCTUnwrap(Bundle(path: path), language)
    }

    func testEveryLanguageHasEveryKey() {
        let ja = table("Localizable", language: "ja")
        XCTAssertGreaterThan(ja.count, 100)
        for language in Self.languages {
            let keys = Set(table("Localizable", language: language).keys)
            XCTAssertEqual(keys, Set(ja.keys), "\(language): missing \(Set(ja.keys).subtracting(keys).sorted()) extra \(keys.subtracting(ja.keys).sorted())")
        }
    }

    func testJapaneseValuesEqualTheirKeys() {
        for (key, value) in table("Localizable", language: "ja") {
            XCTAssertEqual(value as? String, key)
        }
    }

    func testEnglishValuesAreTranslated() throws {
        let en = try bundle(for: "en")
        XCTAssertEqual(en.localizedString(forKey: "履歴", value: nil, table: nil), "History")
        XCTAssertEqual(en.localizedString(forKey: "配置:", value: nil, table: nil), "Position:")
        XCTAssertEqual(String(localized: "上\(5)%", bundle: en, locale: Locale(identifier: "en")), "Up 5%")
    }

    func testEnglishPluralVariation() throws {
        let en = try bundle(for: "en")
        XCTAssertEqual(String(localized: "\(1) フォルダに適用", bundle: en, locale: Locale(identifier: "en")), "Apply to 1 folder")
        XCTAssertEqual(String(localized: "\(2) フォルダに適用", bundle: en, locale: Locale(identifier: "en")), "Apply to 2 folders")
        let dict = table("Localizable", language: "en")
        let entry = try XCTUnwrap(dict["%lld フォルダに適用"] as? [String: Any])
        XCTAssertNotNil(entry["NSStringLocalizedFormatKey"], "plural entry should live in Localizable.stringsdict")
    }

    func testOtherLanguagesDifferFromJapanese() throws {
        for language in Self.languages where language != "ja" {
            let b = try bundle(for: language)
            XCTAssertNotEqual(b.localizedString(forKey: "履歴", value: nil, table: nil), "履歴", language)
        }
    }

    func testInfoPlistIsLocalized() {
        for language in Self.languages {
            let t = table("InfoPlist", language: language)
            XCTAssertNotNil(t["FolderArt Preset Pack"], language)
        }
    }
}
```

- [ ] **Step 7: テスト実行**

Run: テスト実行 (`-only-testing:FolderArtTests/LocalizationTests`)
Expected: 6 tests PASS。`testEnglishPluralVariation` が `String(localized:bundle:locale:)` で複数形にならない場合は、`Bundle.localizedString(forKey:)` の戻り値を `String.localizedStringWithFormat` に通す形 (`String.localizedStringWithFormat(en.localizedString(forKey: "%lld フォルダに適用", value: nil, table: nil), 2)`) に書き換えて通す (どちらも stringsdict を経由する)。

Run: テスト実行 (全体)
Expected: `Executed 198 tests, with 0 failures`、警告 0

- [ ] **Step 8: コミット**

```bash
git add scripts/localization FolderArt/Resources/Localizable.xcstrings FolderArt/Resources/InfoPlist.xcstrings project.yml FolderArt.xcodeproj/project.pbxproj FolderArtTests/LocalizationTests.swift docs/superpowers/specs/2026-09-05-fonts-i18n-contents-design.md
git commit -m "feat: ✨ String Catalog による 8 言語対応 (strings.json から生成、ビルド済みバンドルで完全性を検証)"
```

#### Task 2 付録: `scripts/localization/strings.json` の全文

値の順は `[ja, en, de, es, fr, ko, pt-BR, zh-Hant]`。`||` は単数と複数。「日本語」「繁體中文」は言語メニューの自称 (訳さない `String`) だが、ソース上の日本語リテラルなので `--check` を通すために全言語同じ値で入れてある。

```json
{
  "FolderArt": ["FolderArt", "FolderArt", "FolderArt", "FolderArt", "FolderArt", "FolderArt", "FolderArt", "FolderArt"],
  "お知らせ": ["お知らせ", "Notice", "Hinweis", "Aviso", "Information", "알림", "Aviso", "通知"],
  "履歴": ["履歴", "History", "Verlauf", "Historial", "Historique", "기록", "Histórico", "歷史記錄"],
  "リセット": ["リセット", "Reset", "Zurücksetzen", "Restablecer", "Réinitialiser", "재설정", "Redefinir", "重設"],
  "適用先のフォルダーのアイコンを元に戻す": ["適用先のフォルダーのアイコンを元に戻す", "Restore the icons of the target folders", "Symbole der Zielordner wiederherstellen", "Restaurar los iconos de las carpetas de destino", "Restaurer les icônes des dossiers cibles", "대상 폴더의 아이콘을 원래대로 되돌립니다", "Restaurar os ícones das pastas de destino", "還原目標資料夾的圖示"],
  "リストを空にする": ["リストを空にする", "Clear List", "Liste leeren", "Vaciar la lista", "Vider la liste", "목록 비우기", "Limpar lista", "清空列表"],
  "%lld / %lld": ["%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld", "%lld / %lld"],
  "適用中…": ["適用中…", "Applying…", "Wird angewendet…", "Aplicando…", "Application…", "적용 중…", "Aplicando…", "套用中…"],
  "%lld フォルダに適用": ["%lld フォルダに適用", "Apply to %lld folder||Apply to %lld folders", "Auf %lld Ordner anwenden||Auf %lld Ordner anwenden", "Aplicar a %lld carpeta||Aplicar a %lld carpetas", "Appliquer à %lld dossier||Appliquer à %lld dossiers", "%lld개 폴더에 적용", "Aplicar a %lld pasta||Aplicar a %lld pastas", "套用到 %lld 個資料夾"],
  "選択した %lld フォルダに適用": ["選択した %lld フォルダに適用", "Apply to %lld selected folder||Apply to %lld selected folders", "Auf %lld ausgewählten Ordner anwenden||Auf %lld ausgewählte Ordner anwenden", "Aplicar a %lld carpeta seleccionada||Aplicar a %lld carpetas seleccionadas", "Appliquer à %lld dossier sélectionné||Appliquer à %lld dossiers sélectionnés", "선택한 %lld개 폴더에 적용", "Aplicar a %lld pasta selecionada||Aplicar a %lld pastas selecionadas", "套用到選取的 %lld 個資料夾"],
  "追加": ["追加", "Add", "Hinzufügen", "Añadir", "Ajouter", "추가", "Adicionar", "加入"],
  "画像を選択": ["画像を選択", "Choose Image", "Bild auswählen", "Elegir imagen", "Choisir une image", "이미지 선택", "Escolher imagem", "選擇影像"],
  "保存データの読み込みに失敗しました: %@": ["保存データの読み込みに失敗しました: %@", "Failed to load saved data: %@", "Gespeicherte Daten konnten nicht geladen werden: %@", "No se pudieron cargar los datos guardados: %@", "Impossible de charger les données enregistrées : %@", "저장된 데이터를 불러오지 못했습니다: %@", "Falha ao carregar os dados salvos: %@", "無法載入已儲存的資料：%@"],
  "フォルダーを開けません: %@。フォルダーを追加し直してください。": ["フォルダーを開けません: %@。フォルダーを追加し直してください。", "Cannot open folder: %@. Please add the folder again.", "Ordner kann nicht geöffnet werden: %@. Bitte füge den Ordner erneut hinzu.", "No se puede abrir la carpeta: %@. Vuelve a añadir la carpeta.", "Impossible d’ouvrir le dossier : %@. Veuillez ajouter le dossier à nouveau.", "폴더를 열 수 없습니다: %@. 폴더를 다시 추가해 주세요.", "Não é possível abrir a pasta: %@. Adicione a pasta novamente.", "無法開啟資料夾：%@。請重新加入該資料夾。"],
  "書き出せるお気に入りがありません。": ["書き出せるお気に入りがありません。", "There are no presets to export.", "Es gibt keine Vorlagen zum Exportieren.", "No hay favoritos para exportar.", "Aucun favori à exporter.", "내보낼 즐겨찾기가 없습니다.", "Não há favoritos para exportar.", "沒有可匯出的收藏。"],
  "FolderArt-お気に入り-%@.folderartpack": ["FolderArt-お気に入り-%@.folderartpack", "FolderArt-Presets-%@.folderartpack", "FolderArt-Vorlagen-%@.folderartpack", "FolderArt-Favoritos-%@.folderartpack", "FolderArt-Favoris-%@.folderartpack", "FolderArt-즐겨찾기-%@.folderartpack", "FolderArt-Favoritos-%@.folderartpack", "FolderArt-收藏-%@.folderartpack"],
  "書き出す": ["書き出す", "Export", "Exportieren", "Exportar", "Exporter", "내보내기", "Exportar", "匯出"],
  "パックを書き出せませんでした: %@": ["パックを書き出せませんでした: %@", "Could not export the pack: %@", "Das Paket konnte nicht exportiert werden: %@", "No se pudo exportar el paquete: %@", "Impossible d’exporter le pack : %@", "팩을 내보내지 못했습니다: %@", "Não foi possível exportar o pacote: %@", "無法匯出套件：%@"],
  "読み込む": ["読み込む", "Import", "Importieren", "Importar", "Importer", "가져오기", "Importar", "匯入"],
  "%lld 件のお気に入りを追加しました。": ["%lld 件のお気に入りを追加しました。", "Added %lld preset.||Added %lld presets.", "%lld Vorlage hinzugefügt.||%lld Vorlagen hinzugefügt.", "Se añadió %lld favorito.||Se añadieron %lld favoritos.", "%lld favori ajouté.||%lld favoris ajoutés.", "즐겨찾기 %lld개를 추가했습니다.", "%lld favorito adicionado.||%lld favoritos adicionados.", "已加入 %lld 個收藏。"],
  "%lld 件のお気に入りを追加しました (%lld 件は同じものがあるため省略)。": ["%lld 件のお気に入りを追加しました (%lld 件は同じものがあるため省略)。", "Added %lld preset(s) (%lld skipped as identical).", "%lld Vorlage(n) hinzugefügt (%lld als identisch übersprungen).", "Se añadieron %lld favorito(s) (%lld omitidos por ser idénticos).", "%lld favori(s) ajouté(s) (%lld ignoré(s) car identique(s)).", "즐겨찾기 %lld개를 추가했습니다 (%lld개는 동일하여 생략).", "%lld favorito(s) adicionado(s) (%lld ignorados por serem idênticos).", "已加入 %lld 個收藏（%lld 個因重複而略過）。"],
  "パックを読み込めません: %@": ["パックを読み込めません: %@", "Cannot import the pack: %@", "Das Paket kann nicht importiert werden: %@", "No se puede importar el paquete: %@", "Impossible d’importer le pack : %@", "팩을 가져올 수 없습니다: %@", "Não é possível importar o pacote: %@", "無法匯入套件：%@"],
  "お気に入りのパックを書き出す…": ["お気に入りのパックを書き出す…", "Export Preset Pack…", "Vorlagenpaket exportieren…", "Exportar paquete de favoritos…", "Exporter le pack de favoris…", "즐겨찾기 팩 내보내기…", "Exportar pacote de favoritos…", "匯出收藏套件…"],
  "お気に入りのパックを読み込む…": ["お気に入りのパックを読み込む…", "Import Preset Pack…", "Vorlagenpaket importieren…", "Importar paquete de favoritos…", "Importer un pack de favoris…", "즐겨찾기 팩 가져오기…", "Importar pacote de favoritos…", "匯入收藏套件…"],
  "フォルダーと\n重ねるものを選択": ["フォルダーと\n重ねるものを選択", "Choose a folder\nand an overlay", "Ordner und\nOverlay auswählen", "Elige una carpeta\ny una superposición", "Choisissez un dossier\net une superposition", "폴더와\n겹칠 항목을 선택", "Escolha uma pasta\ne uma sobreposição", "選擇資料夾\n與疊加內容"],
  "お気に入り": ["お気に入り", "Presets", "Vorlagen", "Favoritos", "Favoris", "즐겨찾기", "Favoritos", "收藏"],
  "名前を変更…": ["名前を変更…", "Rename…", "Umbenennen…", "Cambiar nombre…", "Renommer…", "이름 변경…", "Renomear…", "重新命名…"],
  "削除": ["削除", "Delete", "Löschen", "Eliminar", "Supprimer", "삭제", "Excluir", "刪除"],
  "★ を押すと今の見た目を保存できます": ["★ を押すと今の見た目を保存できます", "Press ★ to save the current look", "Mit ★ das aktuelle Aussehen sichern", "Pulsa ★ para guardar el aspecto actual", "Appuyez sur ★ pour enregistrer l’apparence actuelle", "★를 눌러 현재 모습을 저장할 수 있습니다", "Toque ★ para salvar a aparência atual", "按 ★ 可儲存目前的外觀"],
  "今の見た目をお気に入りに保存": ["今の見た目をお気に入りに保存", "Save the current look as a preset", "Aktuelles Aussehen als Vorlage sichern", "Guardar el aspecto actual como favorito", "Enregistrer l’apparence actuelle dans les favoris", "현재 모습을 즐겨찾기에 저장", "Salvar a aparência atual como favorito", "將目前的外觀儲存為收藏"],
  "パックを書き出す…": ["パックを書き出す…", "Export Pack…", "Paket exportieren…", "Exportar paquete…", "Exporter le pack…", "팩 내보내기…", "Exportar pacote…", "匯出套件…"],
  "パックを読み込む…": ["パックを読み込む…", "Import Pack…", "Paket importieren…", "Importar paquete…", "Importer un pack…", "팩 가져오기…", "Importar pacote…", "匯入套件…"],
  "お気に入りのパックを書き出す / 読み込む": ["お気に入りのパックを書き出す / 読み込む", "Export / import preset packs", "Vorlagenpakete exportieren / importieren", "Exportar / importar paquetes de favoritos", "Exporter / importer des packs de favoris", "즐겨찾기 팩 내보내기 / 가져오기", "Exportar / importar pacotes de favoritos", "匯出 / 匯入收藏套件"],
  "お気に入りの名前": ["お気に入りの名前", "Preset Name", "Name der Vorlage", "Nombre del favorito", "Nom du favori", "즐겨찾기 이름", "Nome do favorito", "收藏名稱"],
  "名前": ["名前", "Name", "Name", "Nombre", "Nom", "이름", "Nome", "名稱"],
  "キャンセル": ["キャンセル", "Cancel", "Abbrechen", "Cancelar", "Annuler", "취소", "Cancelar", "取消"],
  "保存": ["保存", "Save", "Sichern", "Guardar", "Enregistrer", "저장", "Salvar", "儲存"],
  "フォルダー (%lld)": ["フォルダー (%lld)", "Folders (%lld)", "Ordner (%lld)", "Carpetas (%lld)", "Dossiers (%lld)", "폴더 (%lld)", "Pastas (%lld)", "資料夾（%lld）"],
  "選択解除": ["選択解除", "Deselect", "Auswahl aufheben", "Deseleccionar", "Désélectionner", "선택 해제", "Desmarcar", "取消選取"],
  "フォルダーを追加…": ["フォルダーを追加…", "Add Folders…", "Ordner hinzufügen…", "Añadir carpetas…", "Ajouter des dossiers…", "폴더 추가…", "Adicionar pastas…", "加入資料夾…"],
  "フォルダーをここにドロップ": ["フォルダーをここにドロップ", "Drop folders here", "Ordner hier ablegen", "Suelta las carpetas aquí", "Déposez les dossiers ici", "여기에 폴더를 놓으세요", "Solte as pastas aqui", "將資料夾拖放到這裡"],
  "フォルダーを選択…": ["フォルダーを選択…", "Choose Folders…", "Ordner auswählen…", "Elegir carpetas…", "Choisir des dossiers…", "폴더 선택…", "Escolher pastas…", "選擇資料夾…"],
  "リストから外す": ["リストから外す", "Remove from list", "Aus der Liste entfernen", "Quitar de la lista", "Retirer de la liste", "목록에서 제거", "Remover da lista", "從列表移除"],
  "画像": ["画像", "Image", "Bild", "Imagen", "Image", "이미지", "Imagem", "影像"],
  "記号": ["記号", "Symbol", "Symbol", "Símbolo", "Symbole", "심볼", "Símbolo", "符號"],
  "絵文字": ["絵文字", "Emoji", "Emoji", "Emoji", "Emoji", "이모지", "Emoji", "表情符號"],
  "文字": ["文字", "Text", "Text", "Texto", "Texte", "문자", "Texto", "文字"],
  "絵文字を入力": ["絵文字を入力", "Enter an emoji", "Emoji eingeben", "Introduce un emoji", "Saisissez un emoji", "이모지 입력", "Digite um emoji", "輸入表情符號"],
  "絵文字パレットを開く": ["絵文字パレットを開く", "Open Emoji Palette", "Emoji-Palette öffnen", "Abrir paleta de emojis", "Ouvrir la palette d’emojis", "이모지 팔레트 열기", "Abrir paleta de emojis", "開啟表情符號面板"],
  "Ctrl + Cmd + Space でも開けます": ["Ctrl + Cmd + Space でも開けます", "You can also press Ctrl + Cmd + Space", "Auch mit Ctrl + Cmd + Leertaste", "También puedes pulsar Ctrl + Cmd + Espacio", "Vous pouvez aussi appuyer sur Ctrl + Cmd + Espace", "Ctrl + Cmd + Space로도 열 수 있습니다", "Você também pode pressionar Ctrl + Cmd + Espaço", "也可以按 Ctrl + Cmd + Space 開啟"],
  "文字を入力 (例: 2026, A, 案)": ["文字を入力 (例: 2026, A, 案)", "Enter text (e.g. 2026, A, NEW)", "Text eingeben (z. B. 2026, A, NEU)", "Introduce texto (p. ej. 2026, A, NUEVO)", "Saisissez du texte (ex. 2026, A, NEW)", "문자 입력 (예: 2026, A, 안)", "Digite o texto (ex.: 2026, A, NOVO)", "輸入文字（例：2026、A、案）"],
  "長い文字は自動で縮小されます。2〜4 文字が読みやすい大きさです。": ["長い文字は自動で縮小されます。2〜4 文字が読みやすい大きさです。", "Long text is scaled down automatically. 2–4 characters stay readable.", "Langer Text wird automatisch verkleinert. 2–4 Zeichen bleiben gut lesbar.", "El texto largo se reduce automáticamente. 2–4 caracteres se leen bien.", "Le texte long est réduit automatiquement. 2 à 4 caractères restent lisibles.", "긴 문자는 자동으로 축소됩니다. 2~4자가 읽기 좋은 크기입니다.", "Textos longos são reduzidos automaticamente. 2–4 caracteres ficam legíveis.", "較長的文字會自動縮小。2～4 個字最易閱讀。"],
  "提案:": ["提案:", "Suggestions:", "Vorschläge:", "Sugerencias:", "Suggestions :", "제안:", "Sugestões:", "建議："],
  "画像を選択...": ["画像を選択...", "Choose Image...", "Bild auswählen...", "Elegir imagen...", "Choisir une image...", "이미지 선택...", "Escolher imagem...", "選擇影像..."],
  "変更...": ["変更...", "Change...", "Ändern...", "Cambiar...", "Modifier...", "변경...", "Alterar...", "更改..."],
  "画像をここにドロップ": ["画像をここにドロップ", "Drop an image here", "Bild hier ablegen", "Suelta una imagen aquí", "Déposez une image ici", "여기에 이미지를 놓으세요", "Solte uma imagem aqui", "將影像拖放到這裡"],
  "検索 (folder, star, camera…)": ["検索 (folder, star, camera…)", "Search (folder, star, camera…)", "Suchen (folder, star, camera…)", "Buscar (folder, star, camera…)", "Rechercher (folder, star, camera…)", "검색 (folder, star, camera…)", "Buscar (folder, star, camera…)", "搜尋（folder、star、camera…）"],
  "配置:": ["配置:", "Position:", "Position:", "Posición:", "Position :", "배치:", "Posição:", "位置："],
  "サイズ:": ["サイズ:", "Size:", "Größe:", "Tamaño:", "Taille :", "크기:", "Tamanho:", "大小："],
  "不透明度:": ["不透明度:", "Opacity:", "Deckkraft:", "Opacidad:", "Opacité :", "불투명도:", "Opacidade:", "不透明度："],
  "上下位置:": ["上下位置:", "Vertical:", "Vertikal:", "Vertical:", "Vertical :", "상하 위치:", "Vertical:", "垂直位置："],
  "中央": ["中央", "Center", "Mitte", "Centro", "Centre", "중앙", "Centro", "置中"],
  "上%lld%%": ["上%lld%%", "Up %lld%%", "Oben %lld%%", "Arriba %lld%%", "Haut %lld%%", "위 %lld%%", "Acima %lld%%", "上 %lld%%"],
  "下%lld%%": ["下%lld%%", "Down %lld%%", "Unten %lld%%", "Abajo %lld%%", "Bas %lld%%", "아래 %lld%%", "Abaixo %lld%%", "下 %lld%%"],
  "色:": ["色:", "Color:", "Farbe:", "Color:", "Couleur :", "색상:", "Cor:", "顏色："],
  "記号と文字に適用": ["記号と文字に適用", "Applies to symbols and text", "Gilt für Symbole und Text", "Se aplica a símbolos y texto", "S’applique aux symboles et au texte", "심볼과 문자에 적용", "Aplica-se a símbolos e texto", "套用於符號與文字"],
  "記号と文字にのみ適用されます": ["記号と文字にのみ適用されます", "Only applies to symbols and text", "Gilt nur für Symbole und Text", "Solo se aplica a símbolos y texto", "S’applique uniquement aux symboles et au texte", "심볼과 문자에만 적용됩니다", "Aplica-se somente a símbolos e texto", "僅套用於符號與文字"],
  "フォルダー形に切り抜く": ["フォルダー形に切り抜く", "Clip to folder shape", "Auf Ordnerform zuschneiden", "Recortar con la forma de la carpeta", "Découper selon la forme du dossier", "폴더 모양으로 자르기", "Recortar no formato da pasta", "裁切為資料夾形狀"],
  "フォント:": ["フォント:", "Font:", "Schrift:", "Fuente:", "Police :", "글꼴:", "Fonte:", "字體："],
  "太さ:": ["太さ:", "Weight:", "Stärke:", "Grosor:", "Graisse :", "굵기:", "Peso:", "粗細："],
  "丸ゴシック (システム)": ["丸ゴシック (システム)", "Rounded (System)", "Rund (System)", "Redondeada (sistema)", "Arrondie (système)", "둥근 고딕 (시스템)", "Arredondada (sistema)", "圓體（系統）"],
  "ヒラギノ角ゴシック": ["ヒラギノ角ゴシック", "Hiragino Sans", "Hiragino Sans", "Hiragino Sans", "Hiragino Sans", "Hiragino Sans", "Hiragino Sans", "Hiragino Sans"],
  "ヒラギノ明朝": ["ヒラギノ明朝", "Hiragino Mincho", "Hiragino Mincho", "Hiragino Mincho", "Hiragino Mincho", "Hiragino Mincho", "Hiragino Mincho", "Hiragino Mincho"],
  "ヒラギノ丸ゴ": ["ヒラギノ丸ゴ", "Hiragino Maru Gothic", "Hiragino Maru Gothic", "Hiragino Maru Gothic", "Hiragino Maru Gothic", "Hiragino Maru Gothic", "Hiragino Maru Gothic", "Hiragino Maru Gothic"],
  "筑紫A丸ゴシック": ["筑紫A丸ゴシック", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic", "Tsukushi A Round Gothic"],
  "クレー": ["クレー", "Klee", "Klee", "Klee", "Klee", "Klee", "Klee", "Klee"],
  "Avenir Next": ["Avenir Next", "Avenir Next", "Avenir Next", "Avenir Next", "Avenir Next", "Avenir Next", "Avenir Next", "Avenir Next"],
  "Menlo (等幅)": ["Menlo (等幅)", "Menlo (Monospaced)", "Menlo (dicktengleich)", "Menlo (monoespaciada)", "Menlo (monospace)", "Menlo (고정폭)", "Menlo (monoespaçada)", "Menlo（等寬）"],
  "その他 (%@)": ["その他 (%@)", "Other (%@)", "Andere (%@)", "Otra (%@)", "Autre (%@)", "기타 (%@)", "Outra (%@)", "其他（%@）"],
  "標準": ["標準", "Regular", "Normal", "Normal", "Normal", "보통", "Normal", "標準"],
  "中太": ["中太", "Medium", "Mittel", "Media", "Moyenne", "중간", "Média", "中等"],
  "半太": ["半太", "Semibold", "Halbfett", "Seminegrita", "Demi-gras", "약간 굵게", "Seminegrito", "半粗"],
  "太字": ["太字", "Bold", "Fett", "Negrita", "Gras", "굵게", "Negrito", "粗體"],
  "特太": ["特太", "Heavy", "Extrafett", "Extranegrita", "Très gras", "매우 굵게", "Extranegrito", "特粗"],
  "極太": ["極太", "Black", "Schwarz", "Black", "Noir", "최대 굵게", "Black", "極粗"],
  "プレビュー": ["プレビュー", "Preview", "Vorschau", "Vista previa", "Aperçu", "미리보기", "Pré-visualização", "預覽"],
  "%lld": ["%lld", "%lld", "%lld", "%lld", "%lld", "%lld", "%lld", "%lld"],
  "Finder での見え方 (px)": ["Finder での見え方 (px)", "As shown in Finder (px)", "Darstellung im Finder (px)", "Como se ve en el Finder (px)", "Aperçu dans le Finder (px)", "Finder에서 보이는 모습 (px)", "Como aparece no Finder (px)", "在 Finder 中的顯示效果（px）"],
  "変更履歴": ["変更履歴", "History", "Verlauf", "Historial", "Historique", "변경 기록", "Histórico", "變更記錄"],
  "閉じる": ["閉じる", "Close", "Schließen", "Cerrar", "Fermer", "닫기", "Fechar", "關閉"],
  "変更履歴はありません": ["変更履歴はありません", "No history yet", "Kein Verlauf vorhanden", "No hay historial", "Aucun historique", "변경 기록이 없습니다", "Nenhum histórico", "沒有變更記錄"],
  "%@ · %@": ["%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@", "%@ · %@"],
  "(旧形式)": ["(旧形式)", "(legacy)", "(altes Format)", "(formato antiguo)", "(ancien format)", "(이전 형식)", "(formato antigo)", "（舊格式）"],
  "(ここからのリセット不可)": ["(ここからのリセット不可)", "(cannot reset from here)", "(Zurücksetzen hier nicht möglich)", "(no se puede restablecer desde aquí)", "(réinitialisation impossible d’ici)", "(여기서는 재설정 불가)", "(não é possível redefinir daqui)", "（無法從此處重設）"],
  "再適用": ["再適用", "Reapply", "Erneut anwenden", "Volver a aplicar", "Réappliquer", "다시 적용", "Reaplicar", "再次套用"],
  "この見た目とフォルダーを画面に戻す": ["この見た目とフォルダーを画面に戻す", "Bring this look and folder back to the window", "Dieses Aussehen und den Ordner ins Fenster zurückholen", "Devolver este aspecto y la carpeta a la ventana", "Rappeler cette apparence et ce dossier dans la fenêtre", "이 모습과 폴더를 화면으로 되돌립니다", "Trazer esta aparência e pasta de volta à janela", "將此外觀與資料夾帶回視窗"],
  "中央オーバーレイ": ["中央オーバーレイ", "Center overlay", "Overlay mittig", "Superposición central", "Superposition centrée", "중앙 오버레이", "Sobreposição central", "置中疊加"],
  "右下バッジ": ["右下バッジ", "Bottom-right badge", "Badge unten rechts", "Insignia inferior derecha", "Badge en bas à droite", "오른쪽 아래 배지", "Selo inferior direito", "右下角標記"],
  "お気に入り「%@」": ["お気に入り「%@」", "Preset “%@”", "Vorlage „%@“", "Favorito «%@»", "Favori « %@ »", "즐겨찾기 “%@”", "Favorito “%@”", "收藏「%@」"],
  "「%@」に一致": ["「%@」に一致", "Matches “%@”", "Passt zu „%@“", "Coincide con «%@»", "Correspond à « %@ »", "“%@”와(과) 일치", "Corresponde a “%@”", "符合「%@」"],
  "記号名「%@」": ["記号名「%@」", "Symbol name “%@”", "Symbolname „%@“", "Nombre de símbolo «%@»", "Nom du symbole « %@ »", "심볼 이름 “%@”", "Nome do símbolo “%@”", "符號名稱「%@」"],
  "検索語「%@」に一致": ["検索語「%@」に一致", "Matches search term “%@”", "Passt zum Suchbegriff „%@“", "Coincide con el término «%@»", "Correspond au terme « %@ »", "검색어 “%@”와(과) 일치", "Corresponde ao termo “%@”", "符合搜尋詞「%@」"],
  "フォルダ名の「%@」": ["フォルダ名の「%@」", "“%@” from the folder name", "„%@“ aus dem Ordnernamen", "«%@» del nombre de la carpeta", "« %@ » du nom du dossier", "폴더 이름의 “%@”", "“%@” do nome da pasta", "資料夾名稱中的「%@」"],
  "中身の多くが画像 (%lld 件)": ["中身の多くが画像 (%lld 件)", "Mostly images inside (%lld file)||Mostly images inside (%lld files)", "Überwiegend Bilder (%lld Datei)||Überwiegend Bilder (%lld Dateien)", "Sobre todo imágenes (%lld archivo)||Sobre todo imágenes (%lld archivos)", "Surtout des images (%lld fichier)||Surtout des images (%lld fichiers)", "내용 대부분이 이미지 (%lld개)", "Principalmente imagens (%lld arquivo)||Principalmente imagens (%lld arquivos)", "內容多為影像（%lld 個）"],
  "中身の多くが動画 (%lld 件)": ["中身の多くが動画 (%lld 件)", "Mostly videos inside (%lld file)||Mostly videos inside (%lld files)", "Überwiegend Videos (%lld Datei)||Überwiegend Videos (%lld Dateien)", "Sobre todo vídeos (%lld archivo)||Sobre todo vídeos (%lld archivos)", "Surtout des vidéos (%lld fichier)||Surtout des vidéos (%lld fichiers)", "내용 대부분이 동영상 (%lld개)", "Principalmente vídeos (%lld arquivo)||Principalmente vídeos (%lld arquivos)", "內容多為影片（%lld 個）"],
  "中身の多くが音楽 (%lld 件)": ["中身の多くが音楽 (%lld 件)", "Mostly music inside (%lld file)||Mostly music inside (%lld files)", "Überwiegend Musik (%lld Datei)||Überwiegend Musik (%lld Dateien)", "Sobre todo música (%lld archivo)||Sobre todo música (%lld archivos)", "Surtout de la musique (%lld fichier)||Surtout de la musique (%lld fichiers)", "내용 대부분이 음악 (%lld개)", "Principalmente música (%lld arquivo)||Principalmente música (%lld arquivos)", "內容多為音樂（%lld 個）"],
  "中身の多くが PDF (%lld 件)": ["中身の多くが PDF (%lld 件)", "Mostly PDFs inside (%lld file)||Mostly PDFs inside (%lld files)", "Überwiegend PDFs (%lld Datei)||Überwiegend PDFs (%lld Dateien)", "Sobre todo PDF (%lld archivo)||Sobre todo PDF (%lld archivos)", "Surtout des PDF (%lld fichier)||Surtout des PDF (%lld fichiers)", "내용 대부분이 PDF (%lld개)", "Principalmente PDFs (%lld arquivo)||Principalmente PDFs (%lld arquivos)", "內容多為 PDF（%lld 個）"],
  "中身の多くがプレゼン (%lld 件)": ["中身の多くがプレゼン (%lld 件)", "Mostly presentations inside (%lld file)||Mostly presentations inside (%lld files)", "Überwiegend Präsentationen (%lld Datei)||Überwiegend Präsentationen (%lld Dateien)", "Sobre todo presentaciones (%lld archivo)||Sobre todo presentaciones (%lld archivos)", "Surtout des présentations (%lld fichier)||Surtout des présentations (%lld fichiers)", "내용 대부분이 프레젠테이션 (%lld개)", "Principalmente apresentações (%lld arquivo)||Principalmente apresentações (%lld arquivos)", "內容多為簡報（%lld 個）"],
  "中身の多くが表計算 (%lld 件)": ["中身の多くが表計算 (%lld 件)", "Mostly spreadsheets inside (%lld file)||Mostly spreadsheets inside (%lld files)", "Überwiegend Tabellen (%lld Datei)||Überwiegend Tabellen (%lld Dateien)", "Sobre todo hojas de cálculo (%lld archivo)||Sobre todo hojas de cálculo (%lld archivos)", "Surtout des feuilles de calcul (%lld fichier)||Surtout des feuilles de calcul (%lld fichiers)", "내용 대부분이 스프레드시트 (%lld개)", "Principalmente planilhas (%lld arquivo)||Principalmente planilhas (%lld arquivos)", "內容多為試算表（%lld 個）"],
  "中身の多くがコード (%lld 件)": ["中身の多くがコード (%lld 件)", "Mostly code inside (%lld file)||Mostly code inside (%lld files)", "Überwiegend Code (%lld Datei)||Überwiegend Code (%lld Dateien)", "Sobre todo código (%lld archivo)||Sobre todo código (%lld archivos)", "Surtout du code (%lld fichier)||Surtout du code (%lld fichiers)", "내용 대부분이 코드 (%lld개)", "Principalmente código (%lld arquivo)||Principalmente código (%lld arquivos)", "內容多為程式碼（%lld 個）"],
  "中身の多くが書類 (%lld 件)": ["中身の多くが書類 (%lld 件)", "Mostly documents inside (%lld file)||Mostly documents inside (%lld files)", "Überwiegend Dokumente (%lld Datei)||Überwiegend Dokumente (%lld Dateien)", "Sobre todo documentos (%lld archivo)||Sobre todo documentos (%lld archivos)", "Surtout des documents (%lld fichier)||Surtout des documents (%lld fichiers)", "내용 대부분이 문서 (%lld개)", "Principalmente documentos (%lld arquivo)||Principalmente documentos (%lld arquivos)", "內容多為文件（%lld 個）"],
  "中身の多くが圧縮ファイル (%lld 件)": ["中身の多くが圧縮ファイル (%lld 件)", "Mostly archives inside (%lld file)||Mostly archives inside (%lld files)", "Überwiegend Archive (%lld Datei)||Überwiegend Archive (%lld Dateien)", "Sobre todo archivos comprimidos (%lld archivo)||Sobre todo archivos comprimidos (%lld archivos)", "Surtout des archives (%lld fichier)||Surtout des archives (%lld fichiers)", "내용 대부분이 압축 파일 (%lld개)", "Principalmente arquivos compactados (%lld arquivo)||Principalmente arquivos compactados (%lld arquivos)", "內容多為壓縮檔（%lld 個）"],
  "中身の多くがアプリ (%lld 件)": ["中身の多くがアプリ (%lld 件)", "Mostly apps inside (%lld item)||Mostly apps inside (%lld items)", "Überwiegend Apps (%lld Objekt)||Überwiegend Apps (%lld Objekte)", "Sobre todo apps (%lld elemento)||Sobre todo apps (%lld elementos)", "Surtout des apps (%lld élément)||Surtout des apps (%lld éléments)", "내용 대부분이 앱 (%lld개)", "Principalmente apps (%lld item)||Principalmente apps (%lld itens)", "內容多為 App（%lld 個）"],
  "中身の画像「%@」": ["中身の画像「%@」", "Image inside: “%@”", "Enthaltenes Bild „%@“", "Imagen del contenido «%@»", "Image du contenu « %@ »", "내용의 이미지 “%@”", "Imagem do conteúdo “%@”", "內容中的影像「%@」"],
  "画像を読み込めません: %@": ["画像を読み込めません: %@", "Cannot read image: %@", "Bild kann nicht gelesen werden: %@", "No se puede leer la imagen: %@", "Impossible de lire l’image : %@", "이미지를 읽을 수 없습니다: %@", "Não é possível ler a imagem: %@", "無法讀取影像：%@"],
  "画像の保存に失敗しました": ["画像の保存に失敗しました", "Failed to save the image", "Bild konnte nicht gesichert werden", "No se pudo guardar la imagen", "Impossible d’enregistrer l’image", "이미지를 저장하지 못했습니다", "Falha ao salvar a imagem", "無法儲存影像"],
  "画像を読み込めません": ["画像を読み込めません", "Cannot read the image", "Bild kann nicht gelesen werden", "No se puede leer la imagen", "Impossible de lire l’image", "이미지를 읽을 수 없습니다", "Não é possível ler a imagem", "無法讀取影像"],
  "このパックは新しいバージョンの FolderArt で作られています。": ["このパックは新しいバージョンの FolderArt で作られています。", "This pack was created with a newer version of FolderArt.", "Dieses Paket wurde mit einer neueren Version von FolderArt erstellt.", "Este paquete se creó con una versión más reciente de FolderArt.", "Ce pack a été créé avec une version plus récente de FolderArt.", "이 팩은 최신 버전의 FolderArt로 만들어졌습니다.", "Este pacote foi criado com uma versão mais recente do FolderArt.", "此套件是以較新版本的 FolderArt 建立的。"],
  "パックを読み込めません (ファイルが壊れています)。": ["パックを読み込めません (ファイルが壊れています)。", "Cannot import the pack (the file is damaged).", "Das Paket kann nicht importiert werden (Datei beschädigt).", "No se puede importar el paquete (el archivo está dañado).", "Impossible d’importer le pack (fichier endommagé).", "팩을 가져올 수 없습니다 (파일이 손상됨).", "Não é possível importar o pacote (o arquivo está danificado).", "無法匯入套件（檔案已損壞）。"],
  "パックの項目が多すぎます (%lld 件、上限 %lld 件)。": ["パックの項目が多すぎます (%lld 件、上限 %lld 件)。", "The pack has too many presets (%lld, limit %lld).", "Das Paket enthält zu viele Vorlagen (%lld, Limit %lld).", "El paquete tiene demasiados favoritos (%lld, límite %lld).", "Le pack contient trop de favoris (%lld, limite %lld).", "팩의 항목이 너무 많습니다 (%lld개, 최대 %lld개).", "O pacote tem favoritos demais (%lld, limite %lld).", "套件的項目過多（%lld 個，上限 %lld 個）。"],
  "「%@」の画像がパックに含まれていません。": ["「%@」の画像がパックに含まれていません。", "The image for “%@” is missing from the pack.", "Das Bild für „%@“ fehlt im Paket.", "Falta la imagen de «%@» en el paquete.", "L’image de « %@ » est absente du pack.", "“%@”의 이미지가 팩에 없습니다.", "A imagem de “%@” não está no pacote.", "套件中缺少「%@」的影像。"],
  "「%@」の画像を読み込めません。": ["「%@」の画像を読み込めません。", "Cannot read the image for “%@”.", "Das Bild für „%@“ kann nicht gelesen werden.", "No se puede leer la imagen de «%@».", "Impossible de lire l’image de « %@ ».", "“%@”의 이미지를 읽을 수 없습니다.", "Não é possível ler a imagem de “%@”.", "無法讀取「%@」的影像。"],
  "「%@」の設定が範囲外です。": ["「%@」の設定が範囲外です。", "The settings for “%@” are out of range.", "Die Einstellungen für „%@“ liegen außerhalb des Bereichs.", "Los ajustes de «%@» están fuera de rango.", "Les réglages de « %@ » sont hors limites.", "“%@”의 설정이 범위를 벗어났습니다.", "As configurações de “%@” estão fora do intervalo.", "「%@」的設定超出範圍。"],
  "パックが大きすぎます (上限 %lld MB)。": ["パックが大きすぎます (上限 %lld MB)。", "The pack is too large (limit %lld MB).", "Das Paket ist zu groß (Limit %lld MB).", "El paquete es demasiado grande (límite %lld MB).", "Le pack est trop volumineux (limite %lld Mo).", "팩이 너무 큽니다 (최대 %lld MB).", "O pacote é grande demais (limite %lld MB).", "套件過大（上限 %lld MB）。"],
  "「%@」の画像が大きすぎます (上限 %lld MB)。": ["「%@」の画像が大きすぎます (上限 %lld MB)。", "The image for “%@” is too large (limit %lld MB).", "Das Bild für „%@“ ist zu groß (Limit %lld MB).", "La imagen de «%@» es demasiado grande (límite %lld MB).", "L’image de « %@ » est trop volumineuse (limite %lld Mo).", "“%@”의 이미지가 너무 큽니다 (최대 %lld MB).", "A imagem de “%@” é grande demais (limite %lld MB).", "「%@」的影像過大（上限 %lld MB）。"],
  "「%@」の画像が見つからないため書き出せません。": ["「%@」の画像が見つからないため書き出せません。", "Cannot export because the image for “%@” was not found.", "Export nicht möglich, da das Bild für „%@“ fehlt.", "No se puede exportar porque no se encontró la imagen de «%@».", "Export impossible : l’image de « %@ » est introuvable.", "“%@”의 이미지를 찾을 수 없어 내보낼 수 없습니다.", "Não é possível exportar porque a imagem de “%@” não foi encontrada.", "找不到「%@」的影像，無法匯出。"],
  "「%@」の記号「%@」はこの macOS にありません。": ["「%@」の記号「%@」はこの macOS にありません。", "Preset “%1$@” uses the symbol “%2$@”, which is not available on this macOS.", "Die Vorlage „%1$@“ verwendet das Symbol „%2$@“, das auf diesem macOS nicht verfügbar ist.", "El favorito «%1$@» usa el símbolo «%2$@», que no está disponible en este macOS.", "Le favori « %1$@ » utilise le symbole « %2$@ », indisponible sur ce macOS.", "“%1$@”의 심볼 “%2$@”은(는) 이 macOS에 없습니다.", "O favorito “%1$@” usa o símbolo “%2$@”, que não está disponível neste macOS.", "「%1$@」的符號「%2$@」在此 macOS 上不存在。"],
  "フォルダーが見つかりません: %@": ["フォルダーが見つかりません: %@", "Folder not found: %@", "Ordner nicht gefunden: %@", "Carpeta no encontrada: %@", "Dossier introuvable : %@", "폴더를 찾을 수 없습니다: %@", "Pasta não encontrada: %@", "找不到資料夾：%@"],
  "アイコンを適用できません: %@。書き込み権限を確認してください。": ["アイコンを適用できません: %@。書き込み権限を確認してください。", "Cannot apply the icon: %@. Check write permissions.", "Symbol kann nicht angewendet werden: %@. Bitte Schreibrechte prüfen.", "No se puede aplicar el icono: %@. Comprueba los permisos de escritura.", "Impossible d’appliquer l’icône : %@. Vérifiez les droits d’écriture.", "아이콘을 적용할 수 없습니다: %@. 쓰기 권한을 확인하세요.", "Não é possível aplicar o ícone: %@. Verifique as permissões de gravação.", "無法套用圖示：%@。請檢查寫入權限。"],
  "アイコンを元に戻せません: %@": ["アイコンを元に戻せません: %@", "Cannot restore the icon: %@", "Symbol kann nicht wiederhergestellt werden: %@", "No se puede restaurar el icono: %@", "Impossible de restaurer l’icône : %@", "아이콘을 되돌릴 수 없습니다: %@", "Não é possível restaurar o ícone: %@", "無法還原圖示：%@"],
  "%lld 件成功、%lld 件失敗": ["%lld 件成功、%lld 件失敗", "%lld succeeded, %lld failed", "%lld erfolgreich, %lld fehlgeschlagen", "%lld correctos, %lld fallidos", "%lld réussis, %lld échoués", "성공 %lld개, 실패 %lld개", "%lld com sucesso, %lld com falha", "成功 %lld 個，失敗 %lld 個"],
  "・%@: %@": ["・%@: %@", "• %@: %@", "• %@: %@", "• %@: %@", "• %@ : %@", "• %@: %@", "• %@: %@", "• %@：%@"],
  "%@ / 巻き戻し失敗: %@": ["%@ / 巻き戻し失敗: %@", "%@ / rollback failed: %@", "%@ / Zurücksetzen fehlgeschlagen: %@", "%@ / no se pudo revertir: %@", "%@ / échec de l’annulation : %@", "%@ / 되돌리기 실패: %@", "%@ / falha ao reverter: %@", "%@ / 回復失敗：%@"],
  "アイコンの合成に失敗しました": ["アイコンの合成に失敗しました", "Failed to compose the icon", "Symbol konnte nicht zusammengesetzt werden", "No se pudo componer el icono", "Impossible de composer l’icône", "아이콘을 합성하지 못했습니다", "Falha ao compor o ícone", "無法合成圖示"],
  "フォルダーへのアクセスが無効になっています。": ["フォルダーへのアクセスが無効になっています。", "Access to the folder is no longer valid.", "Der Zugriff auf den Ordner ist nicht mehr gültig.", "El acceso a la carpeta ya no es válido.", "L’accès au dossier n’est plus valide.", "폴더에 대한 접근이 유효하지 않습니다.", "O acesso à pasta não é mais válido.", "資料夾的存取權已失效。"],
  "履歴の保存に失敗しました: %@": ["履歴の保存に失敗しました: %@", "Failed to save history: %@", "Verlauf konnte nicht gesichert werden: %@", "No se pudo guardar el historial: %@", "Impossible d’enregistrer l’historique : %@", "기록을 저장하지 못했습니다: %@", "Falha ao salvar o histórico: %@", "無法儲存歷史記錄：%@"],
  "ブックマーク作成失敗: %@": ["ブックマーク作成失敗: %@", "Failed to create bookmark: %@", "Lesezeichen konnte nicht erstellt werden: %@", "No se pudo crear el marcador: %@", "Impossible de créer le signet : %@", "북마크 생성 실패: %@", "Falha ao criar o marcador: %@", "無法建立書籤：%@"],
  "ブックマーク解決失敗: %@": ["ブックマーク解決失敗: %@", "Failed to resolve bookmark: %@", "Lesezeichen konnte nicht aufgelöst werden: %@", "No se pudo resolver el marcador: %@", "Impossible de résoudre le signet : %@", "북마크 확인 실패: %@", "Falha ao resolver o marcador: %@", "無法解析書籤：%@"],
  "ブックマークが古くなっています": ["ブックマークが古くなっています", "The bookmark is stale", "Das Lesezeichen ist veraltet", "El marcador está obsoleto", "Le signet est obsolète", "북마크가 오래되었습니다", "O marcador está desatualizado", "書籤已過時"],
  "言語": ["言語", "Language", "Sprache", "Idioma", "Langue", "언어", "Idioma", "語言"],
  "システムに従う": ["システムに従う", "Follow System", "Systemeinstellung", "Seguir el sistema", "Suivre le système", "시스템 설정 따르기", "Seguir o sistema", "跟隨系統"],
  "言語の変更": ["言語の変更", "Language Change", "Sprache ändern", "Cambio de idioma", "Changement de langue", "언어 변경", "Alteração de idioma", "更改語言"],
  "言語の変更は次回起動時に反映されます。今すぐ再起動しますか？ (フォルダーのリストと今の入力は消えます)": ["言語の変更は次回起動時に反映されます。今すぐ再起動しますか？ (フォルダーのリストと今の入力は消えます)", "The language change takes effect the next time FolderArt starts. Restart now? (The folder list and current input will be cleared.)", "Die Sprachänderung wird beim nächsten Start von FolderArt wirksam. Jetzt neu starten? (Die Ordnerliste und die aktuelle Eingabe gehen verloren.)", "El cambio de idioma se aplicará la próxima vez que se abra FolderArt. ¿Reiniciar ahora? (Se borrarán la lista de carpetas y la entrada actual.)", "Le changement de langue prendra effet au prochain lancement de FolderArt. Redémarrer maintenant ? (La liste des dossiers et la saisie en cours seront perdues.)", "언어 변경은 다음에 FolderArt를 시작할 때 적용됩니다. 지금 다시 시작하시겠습니까? (폴더 목록과 현재 입력은 사라집니다)", "A alteração de idioma será aplicada na próxima vez que o FolderArt for aberto. Reiniciar agora? (A lista de pastas e a entrada atual serão perdidas.)", "語言變更將在下次啟動 FolderArt 時生效。要立即重新啟動嗎？（資料夾列表與目前的輸入將會清除）"],
  "再起動": ["再起動", "Restart", "Neu starten", "Reiniciar", "Redémarrer", "다시 시작", "Reiniciar", "重新啟動"],
  "あとで": ["あとで", "Later", "Später", "Más tarde", "Plus tard", "나중에", "Depois", "稍後"],
  "日本語": ["日本語", "日本語", "日本語", "日本語", "日本語", "日本語", "日本語", "日本語"],
  "繁體中文": ["繁體中文", "繁體中文", "繁體中文", "繁體中文", "繁體中文", "繁體中文", "繁體中文", "繁體中文"],
  "再起動できませんでした: %@": ["再起動できませんでした: %@", "Could not restart: %@", "Neustart nicht möglich: %@", "No se pudo reiniciar: %@", "Impossible de redémarrer : %@", "다시 시작할 수 없습니다: %@", "Não foi possível reiniciar: %@", "無法重新啟動：%@"]
}
```

---

### Task 3: FontCatalog (厳選 8 家族、家族 + 太さの解決) と OverlayRenderer の委譲

**Files:**
- Create: `FolderArt/Services/FontCatalog.swift`
- Modify: `FolderArt/Models/CodableColor.swift` (`FontWeightValue.displayName`、`import SwiftUI`)
- Modify: `FolderArt/Services/OverlayRenderer.swift:119-130` (`makeFont`)
- Test: `FolderArtTests/FontCatalogTests.swift`
- Test: `FolderArtTests/OverlayRendererTests.swift` (1 件追加)

**Interfaces:**
- Consumes: `CompositionSettings.fontName: String?` / `fontWeight: FontWeightValue` (既存)、`FontWeightValue.nsWeight` (既存)
- Produces:
  - `struct FontChoice: Identifiable { let family: String?; let title: LocalizedStringKey; var id: String }` (`family == nil` = 丸ゴシック)
  - `enum FontCatalog { static let choices: [FontChoice]; static let installedFamilies: Set<String>; static func available(families: Set<String> = installedFamilies) -> [FontChoice]; static func choices(including current: String?, available: [FontChoice]) -> [FontChoice]; static func font(family: String?, weight: FontWeightValue, size: CGFloat, families: Set<String> = installedFamilies) -> NSFont; static func systemRounded(weight: FontWeightValue, size: CGFloat) -> NSFont }`
  - `FontWeightValue.displayName: LocalizedStringKey`
  - `OverlayRenderer.makeFont(size:settings:)` は `FontCatalog.font` を呼ぶだけになる (署名は変えない)

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/FontCatalogTests.swift`:

```swift
import XCTest
import AppKit
@testable import FolderArt

final class FontCatalogTests: XCTestCase {

    func testNilFamilyIsSystemRounded() {
        let font = FontCatalog.font(family: nil, weight: .bold, size: 100, families: [])
        XCTAssertTrue(font.fontName.contains("Rounded"), font.fontName)
    }

    func testKnownFamilyResolvesToNearestWeight() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Sans"), "Hiragino Sans is not installed")
        let regular = FontCatalog.font(family: "Hiragino Sans", weight: .regular, size: 100)
        let bold = FontCatalog.font(family: "Hiragino Sans", weight: .bold, size: 100)
        let black = FontCatalog.font(family: "Hiragino Sans", weight: .black, size: 100)
        XCTAssertEqual(regular.familyName, "Hiragino Sans")
        XCTAssertEqual(regular.fontName, "HiraginoSans-W3")
        XCTAssertEqual(bold.fontName, "HiraginoSans-W6")
        XCTAssertEqual(black.fontName, "HiraginoSans-W8")
    }

    func testSingleWeightFamilyIgnoresWeight() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Maru Gothic ProN"), "Hiragino Maru Gothic ProN is not installed")
        for weight in FontWeightValue.allCases {
            XCTAssertEqual(FontCatalog.font(family: "Hiragino Maru Gothic ProN", weight: weight, size: 100).fontName, "HiraMaruProN-W4", "\(weight)")
        }
    }

    func testUnknownFamilyFallsBackToSystemRounded() {
        let font = FontCatalog.font(family: "No Such Family XYZ", weight: .bold, size: 100, families: [])
        XCTAssertTrue(font.fontName.contains("Rounded"), font.fontName)
    }

    func testPostScriptNameStillResolvesForOldPacks() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Sans"), "Hiragino Sans is not installed")
        // families に無い名前は NSFont(name:) の経路 (1.3.0 までのパックに PostScript 名が入っていた場合の互換)
        let font = FontCatalog.font(family: "HiraginoSans-W6", weight: .regular, size: 100)
        XCTAssertEqual(font.fontName, "HiraginoSans-W6")
    }

    func testAvailableKeepsDefaultAndDropsMissingFamilies() {
        let list = FontCatalog.available(families: ["Menlo"])
        XCTAssertEqual(list.map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.available(families: []).map(\.family), [nil])
        XCTAssertEqual(FontCatalog.choices.count, 8)
        XCTAssertNil(FontCatalog.choices.first?.family)
    }

    func testChoicesIncludingUnknownCurrentAppendsOther() {
        let base = FontCatalog.available(families: ["Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: nil, available: base).map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: "Menlo", available: base).map(\.family), [nil, "Menlo"])
        XCTAssertEqual(FontCatalog.choices(including: "Zapfino", available: base).map(\.family), [nil, "Menlo", "Zapfino"])
        XCTAssertEqual(FontCatalog.choices(including: "Zapfino", available: base).last?.id, "Zapfino")
    }

    func testWeightDisplayNamesAreDistinct() {
        // LocalizedStringKey は比較しにくいので、描画に使う NSFont.Weight が 6 種で異なることだけ見る
        XCTAssertEqual(Set(FontWeightValue.allCases.map(\.nsWeight.rawValue)).count, 6)
    }
}
```

`FolderArtTests/OverlayRendererTests.swift` に追加 (既存の `render(_:settings:)` ヘルパを使う):

```swift
    func testTextRendersWithCustomFamily() throws {
        try XCTSkipUnless(FontCatalog.installedFamilies.contains("Hiragino Mincho ProN"), "Hiragino Mincho ProN is not installed")
        var settings = CompositionSettings()
        settings.fontName = "Hiragino Mincho ProN"
        settings.tintColor = CodableColor(red: 1, green: 0, blue: 0, alpha: 1)
        let image = try XCTUnwrap(render(.text("明"), settings: settings))
        XCTAssertTrue(TestSupport.contains(color: .red, in: image))
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/FontCatalogTests`)
Expected: コンパイルエラー (`FontCatalog` が無い)

- [ ] **Step 3: FontWeightValue.displayName**

`FolderArt/Models/CodableColor.swift` の先頭 `import AppKit` の下に `import SwiftUI` を足し、末尾に追加:

```swift
extension FontWeightValue {
    /// Picker の表示名 (太さの UI は第3段階で開放)
    var displayName: LocalizedStringKey {
        switch self {
        case .regular:  return "標準"
        case .medium:   return "中太"
        case .semibold: return "半太"
        case .bold:     return "太字"
        case .heavy:    return "特太"
        case .black:    return "極太"
        }
    }
}
```

- [ ] **Step 4: FontCatalog を書く**

`FolderArt/Services/FontCatalog.swift`:

```swift
import AppKit
import SwiftUI

/// 文字のフォントの選択肢 1 つ。family が nil ならシステム丸ゴシック (CompositionSettings.fontName の nil と同じ意味)
struct FontChoice: Identifiable {
    let family: String?
    let title: LocalizedStringKey
    var id: String { family ?? "" }
}

/// macOS 同梱の厳選フォントと、家族名 + 太さから NSFont を作る解決規則。
/// fontName にはファミリ名を入れる (PostScript 名ではない)。別の Mac に無い家族は既定に落ちる。
enum FontCatalog {

    /// この順に Picker へ出す。どの Mac にもあるものだけ (macOS 13 の標準構成で確認)
    static let choices: [FontChoice] = [
        FontChoice(family: nil, title: "丸ゴシック (システム)"),
        FontChoice(family: "Hiragino Sans", title: "ヒラギノ角ゴシック"),
        FontChoice(family: "Hiragino Mincho ProN", title: "ヒラギノ明朝"),
        FontChoice(family: "Hiragino Maru Gothic ProN", title: "ヒラギノ丸ゴ"),
        FontChoice(family: "Tsukushi A Round Gothic", title: "筑紫A丸ゴシック"),
        FontChoice(family: "Klee", title: "クレー"),
        FontChoice(family: "Avenir Next", title: "Avenir Next"),
        FontChoice(family: "Menlo", title: "Menlo (等幅)"),
    ]

    /// この Mac にある家族名。起動後 1 回だけ取得 (描画のたびに NSFontManager を引かない。起動後に入れたフォントは次回起動から)
    static let installedFamilies: Set<String> = Set(NSFontManager.shared.availableFontFamilies)

    /// この Mac にあるものだけ。先頭 (nil = 丸ゴシック) は常に含む
    static func available(families: Set<String> = installedFamilies) -> [FontChoice] {
        choices.filter { choice in choice.family.map { families.contains($0) } ?? true }
    }

    /// Picker 用: 今の値が一覧に無ければ「その他 (名前)」を末尾に足す (SwiftUI の Picker は選択値が一覧に無いと空表示になる)。
    /// 設定の値は書き換えない。選び直せばこの項目は消える
    static func choices(including current: String?, available: [FontChoice]) -> [FontChoice] {
        guard let current, !available.contains(where: { $0.family == current }) else { return available }
        return available + [FontChoice(family: current, title: "その他 (\(current))")]
    }

    /// 解決順: nil → 丸ゴシック / 家族がある → 家族 + 太さの descriptor (無い太さは一番近い顔) /
    /// 家族が無い → NSFont(name:) (PostScript 名の互換) / どれも無い → 丸ゴシック
    static func font(family: String?, weight: FontWeightValue, size: CGFloat,
                     families: Set<String> = installedFamilies) -> NSFont {
        if let family {
            if families.contains(family) {
                let descriptor = NSFontDescriptor(fontAttributes: [
                    .family: family,
                    .traits: [NSFontDescriptor.TraitKey.weight: weight.nsWeight.rawValue],
                ])
                // 家族が無いと別の家族に置き換わることがあるので、返った家族名を確かめる
                if let font = NSFont(descriptor: descriptor, size: size), font.familyName == family {
                    return font
                }
            }
            if let named = NSFont(name: family, size: size) {
                return named
            }
        }
        return systemRounded(weight: weight, size: size)
    }

    /// システムフォントの rounded デザイン (1.3.0 までの既定と同じ)
    static func systemRounded(weight: FontWeightValue, size: CGFloat) -> NSFont {
        let system = NSFont.systemFont(ofSize: size, weight: weight.nsWeight)
        if let rounded = system.fontDescriptor.withDesign(.rounded),
           let font = NSFont(descriptor: rounded, size: size) {
            return font
        }
        return system
    }
}
```

- [ ] **Step 5: OverlayRenderer.makeFont を委譲にする**

`FolderArt/Services/OverlayRenderer.swift` の `makeFont` (119-130 行) を置き換える:

```swift
    /// フォントの解決は FontCatalog (nil = 丸ゴシック、家族 + 太さ、PostScript 名の互換、既定への退避)
    static func makeFont(size: CGFloat, settings: CompositionSettings) -> NSFont {
        FontCatalog.font(family: settings.fontName, weight: settings.fontWeight, size: size)
    }
```

- [ ] **Step 6: xcodegen とテスト**

```bash
xcodegen generate
```

Run: テスト実行 (`-only-testing:FolderArtTests/FontCatalogTests -only-testing:FolderArtTests/OverlayRendererTests`)
Expected: 全 PASS (Hiragino が無い Mac ではスキップが出る)

Run: テスト実行 (全体)
Expected: `Executed 207 tests, with 0 failures` (192 + Task 2 の 6 + 9)、警告 0

- [ ] **Step 7: コミット**

```bash
git add FolderArt/Services/FontCatalog.swift FolderArt/Models/CodableColor.swift FolderArt/Services/OverlayRenderer.swift FolderArt.xcodeproj/project.pbxproj FolderArtTests/FontCatalogTests.swift FolderArtTests/OverlayRendererTests.swift
git commit -m "feat: ✨ FontCatalog を追加 (macOS 同梱の厳選 8 家族、家族 + 太さの解決、PostScript 名の互換)"
```

---

### Task 4: フォント・太さの Picker (ControlsView) とウィンドウの高さ

**Files:**
- Modify: `FolderArt/Views/ControlsView.swift` (全体を書き直す)
- Modify: `FolderArt/ContentView.swift:66-70,78` (`showsFont` / `showsWeight`、`minHeight`)
- Modify: `FolderArt/FolderArtApp.swift:13` (`defaultSize`)

**Interfaces:**
- Consumes: Task 3 の `FontCatalog.available()` / `choices(including:available:)` / `FontWeightValue.displayName`
- Produces: `ControlsView(settings:showsTint:showsFont:showsWeight:sizeLockedByFill:)`

- [ ] **Step 1: ControlsView を書き直す**

`FolderArt/Views/ControlsView.swift` 全体:

```swift
import SwiftUI

struct ControlsView: View {
    @Binding var settings: CompositionSettings
    /// 画像タブでは色は効かないので無効表示にする
    var showsTint: Bool = true
    /// フォントは文字タブでのみ効く
    var showsFont: Bool = false
    /// 太さは記号と文字で効く (画像・絵文字では無効表示)
    var showsWeight: Bool = false
    /// 切り抜き ON + 中央でサイズが効かなくなるのは画像 (敷き詰め) だけ。記号・絵文字・文字ではサイズは常に有効
    var sizeLockedByFill: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            HStack {
                Text("配置:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker("", selection: $settings.position) {
                    ForEach(IconPosition.allCases, id: \.self) { pos in
                        Text(pos.displayName).tag(pos)
                    }
                }
                .pickerStyle(.radioGroup)
                .labelsHidden()
            }

            Divider()

            SliderRow(label: "サイズ:", value: $settings.scale, range: CompositionSettings.scaleRange,
                      format: { "\(Int($0 * 100))%" })
                .disabled(sizeLockedByFill && settings.clipToFolderShape && settings.position == .center)
                .opacity(sizeLockedByFill && settings.clipToFolderShape && settings.position == .center ? 0.4 : 1.0)

            SliderRow(label: "不透明度:", value: $settings.opacity, range: CompositionSettings.opacityRange,
                      format: { "\(Int($0 * 100))%" })

            SliderRow(label: "上下位置:", value: $settings.verticalOffset, range: CompositionSettings.verticalOffsetRange,
                      format: { v in
                          if abs(v) < 0.01 { return String(localized: "中央") }
                          return v > 0 ? String(localized: "上\(Int(v * 100))%") : String(localized: "下\(Int(-v * 100))%")
                      })

            HStack {
                Text("色:").font(.callout).frame(width: 80, alignment: .trailing)
                ColorPicker("", selection: tintBinding, supportsOpacity: false)
                    .labelsHidden()
                    .disabled(!showsTint)
                    .opacity(showsTint ? 1 : 0.4)
                (showsTint ? Text("記号と文字に適用") : Text("記号と文字にのみ適用されます"))
                    .font(.caption).foregroundColor(.secondary)
            }

            HStack {
                Text("フォント:").font(.callout).frame(width: 80, alignment: .trailing)
                // 今の値が一覧に無いとき (別の Mac のパックなど) は「その他 (名前)」を足して選択が空にならないようにする
                Picker("", selection: $settings.fontName) {
                    ForEach(FontCatalog.choices(including: settings.fontName, available: FontCatalog.available())) { choice in
                        Text(choice.title).tag(choice.family)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 220)
                .disabled(!showsFont)
                .opacity(showsFont ? 1 : 0.4)
            }

            HStack {
                Text("太さ:").font(.callout).frame(width: 80, alignment: .trailing)
                Picker("", selection: $settings.fontWeight) {
                    ForEach(FontWeightValue.allCases, id: \.self) { weight in
                        Text(weight.displayName).tag(weight)
                    }
                }
                .pickerStyle(.menu)
                .labelsHidden()
                .frame(maxWidth: 140)
                .disabled(!showsWeight)
                .opacity(showsWeight ? 1 : 0.4)
            }

            Divider()

            HStack {
                Text("").frame(width: 80, alignment: .trailing)
                // 表示名を内部名 (clipToFolderShape) と一致させる
                Toggle("フォルダー形に切り抜く", isOn: $settings.clipToFolderShape)
                    .toggleStyle(.checkbox)
            }
        }
        .padding(.horizontal)
    }

    private var tintBinding: Binding<Color> {
        Binding(
            get: { Color(nsColor: settings.tintColor.nsColor) },
            set: { settings.tintColor = CodableColor(NSColor($0)) }
        )
    }
}

private struct SliderRow: View {
    let label: LocalizedStringKey
    @Binding var value: Double
    let range: ClosedRange<Double>
    let format: (Double) -> String

    var body: some View {
        HStack {
            Text(label).font(.callout).frame(width: 80, alignment: .trailing)
            Slider(value: $value, in: range)
            Text(format(value)).font(.callout).monospacedDigit().frame(width: 44, alignment: .trailing)
        }
    }
}
```

(`$settings.fontName` は `Binding<String?>`。`tag(choice.family)` も `String?` なので型が揃う)

- [ ] **Step 2: ContentView と FolderArtApp**

`FolderArt/ContentView.swift` の `ControlsView(...)` 呼び出しを次に置き換える:

```swift
                ControlsView(settings: settingsBinding,
                             showsTint: model.overlay.activeTab == .symbol || model.overlay.activeTab == .text,
                             showsFont: model.overlay.activeTab == .text,
                             showsWeight: model.overlay.activeTab == .symbol || model.overlay.activeTab == .text,
                             sizeLockedByFill: model.overlay.activeTab == .image)
                    .frame(maxWidth: .infinity)
```

同ファイルの `.frame(minWidth: 760, minHeight: 720)` を `.frame(minWidth: 760, minHeight: 780)` に。

`FolderArt/FolderArtApp.swift` の `.defaultSize(width: 760, height: 720)` を `.defaultSize(width: 760, height: 780)` に。

- [ ] **Step 3: ビルドと実機確認**

Run: テスト実行 (全体)
Expected: `Executed 207 tests, with 0 failures`、警告 0

実機: `xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -configuration Debug -destination 'platform=macOS' -derivedDataPath build 2>&1 | tail -1` の後 `open build/Build/Products/Debug/FolderArt.app`。文字タブで「フォント:」と「太さ:」が有効、記号タブで太さだけ有効、画像・絵文字タブで両方 0.4 表示、フォントを変えるとプレビューが変わる、ウィンドウの下端が切れていないことを目で見る。

- [ ] **Step 4: コミット**

```bash
git add FolderArt/Views/ControlsView.swift FolderArt/ContentView.swift FolderArt/FolderArtApp.swift
git commit -m "feat: ✨ 文字のフォントと記号・文字の太さを選ぶ Picker を設定に追加"
```

---

### Task 5: ContentScanner (直下の種類と代表画像) と辞書の代表キー

**Files:**
- Create: `FolderArt/Services/ContentScanner.swift`
- Modify: `FolderArt/Services/SuggestionDictionary.swift` (`entry(forKey:)`)
- Modify: `FolderArt/Resources/suggestions.json` (presentation / spreadsheet の 2 項目)
- Test: `FolderArtTests/ContentScannerTests.swift`
- Test: `FolderArtTests/SuggestionDictionaryTests.swift` (1 件追加)

**Interfaces:**
- Consumes: `SuggestionEntry` / `SuggestionDictionary` (既存)
- Produces:
  - `enum ContentKind: CaseIterable, Hashable, Sendable { case image, video, audio, pdf, presentation, spreadsheet, code, document, archive, app, folder; var dictionaryKey: String?; func reason(count: Int) -> String?; static func classify(type: UTType?, isDirectory: Bool, isPackage: Bool) -> ContentKind? }`
  - `struct RepresentativeImage: Equatable, Sendable { let url: URL; let modificationDate: Date; let thumbnailPNG: Data }` (等価判定は url + modificationDate)
  - `struct ContentSummary: Equatable, Sendable { let counts: [ContentKind: Int]; let dominant: ContentKind?; let representative: RepresentativeImage?; static func dominant(of:) -> ContentKind? }`
  - `enum ContentScanner { static let entryLimit = 1000; static let maxImageBytes; static let representableTypes: [UTType]; static let iconFileName = "Icon\r"; static func scan(_ folder: URL, limit: Int = entryLimit, maxImageBytes: Int = maxImageBytes) -> ContentSummary?; static func thumbnailPNG(of url: URL, maxPixel: Int = 256) -> Data? }`
  - `SuggestionDictionary.entry(forKey:) -> SuggestionEntry?`

- [ ] **Step 1: 辞書に 2 項目を足す**

`FolderArt/Resources/suggestions.json` の末尾 (最後の項目の後、`]` の前) に追加。直前の項目の末尾に `,` を付けること:

```json
  {"keys": ["プレゼン", "スライド", "presentation", "presentations", "slides", "slide", "keynote", "pptx"], "symbol": "play.rectangle.fill", "emoji": "📽️"},
  {"keys": ["表計算", "スプレッドシート", "spreadsheet", "spreadsheets", "excel", "xlsx", "numbers"], "symbol": "tablecells.fill", "emoji": "📊"}
```

(記号 2 つは macOS 13 の SF Symbols にあり、制限付きでないことを 2026-09-05 に確認済み。既存のキーと重複しないことも確認済み)

- [ ] **Step 2: 失敗するテストを書く**

`FolderArtTests/SuggestionDictionaryTests.swift` に追加:

```swift
    /// 中身からの提案は辞書の代表キーで記号・絵文字を引く。folder 以外の全種類が引けて、記号と絵文字の両方を持つ
    func testEveryContentKindHasADictionaryEntry() {
        let dict = SuggestionDictionary.load(bundle: Bundle(for: SuggestionDictionaryTests.self))
        for kind in ContentKind.allCases {
            guard let key = kind.dictionaryKey else { XCTAssertEqual(kind, .folder); continue }
            let entry = dict.entry(forKey: key)
            XCTAssertNotNil(entry, "no entry for \(kind) (key \(key))")
            XCTAssertNotNil(entry?.symbol, "\(kind)")
            XCTAssertNotNil(entry?.emoji, "\(kind)")
        }
        XCTAssertNil(dict.entry(forKey: "no-such-key"))
    }
```

`FolderArtTests/ContentScannerTests.swift`:

```swift
import XCTest
import AppKit
import UniformTypeIdentifiers
@testable import FolderArt

final class ContentScannerTests: XCTestCase {
    private var root: URL!

    override func setUp() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("ContentScannerTests_\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDown() {
        try? FileManager.default.removeItem(at: root)
    }

    // MARK: - helpers

    @discardableResult
    private func touch(_ name: String, in dir: URL? = nil, date: Date? = nil) throws -> URL {
        let url = (dir ?? root).appendingPathComponent(name)
        try Data().write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    /// 実際に復号できる PNG (単色)
    @discardableResult
    private func png(_ name: String, size: CGSize = CGSize(width: 64, height: 32), in dir: URL? = nil, date: Date? = nil) throws -> URL {
        let image = TestSupport.makeSolidImage(size: size, color: .red)
        let data = try XCTUnwrap(TestSupport.bitmap(of: image).representation(using: .png, properties: [:]))
        let url = (dir ?? root).appendingPathComponent(name)
        try data.write(to: url)
        if let date { try FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: url.path) }
        return url
    }

    /// EXIF の向き (orientation 6 = 90 度回転) を付けた JPEG
    private func rotatedJPEG(_ name: String, size: CGSize) throws -> URL {
        let image = TestSupport.makeSolidImage(size: size, color: .blue)
        let cg = try XCTUnwrap(image.cgImage(forProposedRect: nil, context: nil, hints: nil))
        let url = root.appendingPathComponent(name)
        let dest = try XCTUnwrap(CGImageDestinationCreateWithURL(url as CFURL, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(dest, cg, [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(dest))
        return url
    }

    private func pixelSize(ofPNG data: Data) throws -> CGSize {
        let rep = try XCTUnwrap(NSBitmapImageRep(data: data))
        return CGSize(width: rep.pixelsWide, height: rep.pixelsHigh)
    }

    // MARK: - classify

    func testClassifyFollowsPriorityOrder() {
        XCTAssertEqual(ContentKind.classify(type: nil, isDirectory: true, isPackage: false), .folder)
        XCTAssertEqual(ContentKind.classify(type: .application, isDirectory: true, isPackage: true), .app)
        XCTAssertEqual(ContentKind.classify(type: .png, isDirectory: false, isPackage: false), .image)
        XCTAssertEqual(ContentKind.classify(type: .mpeg4Movie, isDirectory: false, isPackage: false), .video)
        XCTAssertEqual(ContentKind.classify(type: .mp3, isDirectory: false, isPackage: false), .audio)
        XCTAssertEqual(ContentKind.classify(type: .pdf, isDirectory: false, isPackage: false), .pdf)
        XCTAssertEqual(ContentKind.classify(type: .presentation, isDirectory: false, isPackage: false), .presentation)
        XCTAssertEqual(ContentKind.classify(type: .spreadsheet, isDirectory: false, isPackage: false), .spreadsheet)
        XCTAssertEqual(ContentKind.classify(type: .swiftSource, isDirectory: false, isPackage: false), .code)   // .text より先
        XCTAssertEqual(ContentKind.classify(type: .plainText, isDirectory: false, isPackage: false), .document)
        XCTAssertEqual(ContentKind.classify(type: .zip, isDirectory: false, isPackage: false), .archive)
        XCTAssertNil(ContentKind.classify(type: .data, isDirectory: false, isPackage: false))
        XCTAssertNil(ContentKind.classify(type: nil, isDirectory: false, isPackage: false))
    }

    func testDominantPrefersEarlierKindOnTie() {
        XCTAssertEqual(ContentSummary.dominant(of: [.image: 2, .document: 2]), .image)
        XCTAssertEqual(ContentSummary.dominant(of: [.document: 3, .audio: 2]), .document)
        XCTAssertNil(ContentSummary.dominant(of: [:]))
        XCTAssertNil(ContentSummary.dominant(of: [.image: 0]))
    }

    // MARK: - scan

    func testCountsByKindAndPicksDominantWithRepresentative() throws {
        try png("a.png"); try png("b.png"); try png("c.png")
        try touch("notes.txt"); try touch("song.mp3")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.image: 3, .document: 1, .audio: 1])
        XCTAssertEqual(summary.dominant, .image)
        XCTAssertNotNil(summary.representative)
    }

    func testHiddenFilesAndIconFileAreSkipped() throws {
        try png(".hidden.png")
        try touch(ContentScanner.iconFileName)
        try touch("readme.md")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.document: 1])
        XCTAssertNil(summary.representative)
    }

    func testSubfoldersCountAsFolderAndGiveNoRepresentative() throws {
        for name in ["one", "two", "three"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
        }
        try png("x.png")
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts, [.folder: 3, .image: 1])
        XCTAssertEqual(summary.dominant, .folder)
        XCTAssertNil(summary.representative)
    }

    func testRepresentativeIsNewestThenByName() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        try png("a.png", date: old)
        try png("c.png", date: new)
        try png("b.png", date: new)
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        let rep = try XCTUnwrap(summary.representative)
        XCTAssertEqual(rep.url.lastPathComponent, "b.png")
        XCTAssertEqual(rep.modificationDate, new)
    }

    func testRepresentativeSkipsUnsupportedFormatsAndHugeFiles() throws {
        let old = Date(timeIntervalSince1970: 1_000_000)
        let new = Date(timeIntervalSince1970: 2_000_000)
        try png("ok.png", date: old)
        try touch("newer.psd", date: new)   // 画像には数えるが代表にはしない (パネルで選べる形式ではない)
        var summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertEqual(summary.counts[.image], 2)
        XCTAssertEqual(summary.representative?.url.lastPathComponent, "ok.png")

        // 上限を下げると ok.png も代表にならない (種類の多数派はそのまま)
        summary = try XCTUnwrap(ContentScanner.scan(root, maxImageBytes: 10))
        XCTAssertEqual(summary.dominant, .image)
        XCTAssertNil(summary.representative)
    }

    func testLimitStopsEnumeration() throws {
        for i in 0..<5 { try touch("f\(i).txt") }
        let summary = try XCTUnwrap(ContentScanner.scan(root, limit: 3))
        XCTAssertEqual(summary.counts.values.reduce(0, +), 3)
    }

    func testMissingFolderIsNil() {
        XCTAssertNil(ContentScanner.scan(root.appendingPathComponent("does-not-exist")))
    }

    func testEmptyFolderIsEmptySummary() throws {
        let summary = try XCTUnwrap(ContentScanner.scan(root))
        XCTAssertTrue(summary.counts.isEmpty)
        XCTAssertNil(summary.dominant)
    }

    func testCancelledTaskGivesNil() async throws {
        try touch("a.txt")
        let folder: URL = root
        let task = Task.detached { () -> ContentSummary? in
            try? await Task.sleep(nanoseconds: 200_000_000)   // cancel 済みなら即座に抜ける
            return ContentScanner.scan(folder)
        }
        task.cancel()
        let result = await task.value
        XCTAssertNil(result)
    }

    // MARK: - thumbnail

    func testThumbnailIsAtMost256AndKeepsAspect() throws {
        let url = try png("wide.png", size: CGSize(width: 800, height: 400))
        let data = try XCTUnwrap(ContentScanner.thumbnailPNG(of: url))
        XCTAssertEqual(try pixelSize(ofPNG: data), CGSize(width: 256, height: 128))
        XCTAssertTrue(AssetStore.isPNG(data))
    }

    func testThumbnailAppliesExifOrientation() throws {
        let url = try rotatedJPEG("rotated.jpg", size: CGSize(width: 400, height: 200))
        let data = try XCTUnwrap(ContentScanner.thumbnailPNG(of: url))
        let size = try pixelSize(ofPNG: data)
        XCTAssertGreaterThan(size.height, size.width, "\(size)")
    }

    func testThumbnailOfNonImageIsNil() throws {
        let url = try touch("x.txt")
        XCTAssertNil(ContentScanner.thumbnailPNG(of: url))
    }
}
```

- [ ] **Step 3: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/ContentScannerTests`)
Expected: コンパイルエラー (`ContentKind` などが無い)

- [ ] **Step 4: SuggestionDictionary.entry(forKey:)**

`FolderArt/Services/SuggestionDictionary.swift` の `SuggestionDictionary` に追加:

```swift
    /// 代表キー (小文字) を持つ項目。中身からの提案が種類 → 記号・絵文字を引くのに使う
    func entry(forKey key: String) -> SuggestionEntry? {
        entries.first { $0.keys.contains(key) }
    }
```

- [ ] **Step 5: ContentScanner を書く**

`FolderArt/Services/ContentScanner.swift`:

```swift
import AppKit
import ImageIO
import UniformTypeIdentifiers

/// フォルダ直下のファイルの種類。判定と多数派の同数の優先順はこの列挙順
enum ContentKind: CaseIterable, Hashable, Sendable {
    case image, video, audio, pdf, presentation, spreadsheet, code, document, archive, app, folder

    /// 辞書 (suggestions.json) の代表キー。folder はチップを出さないので nil
    var dictionaryKey: String? {
        switch self {
        case .image:        return "photo"
        case .video:        return "video"
        case .audio:        return "music"
        case .pdf:          return "pdf"
        case .presentation: return "presentation"
        case .spreadsheet:  return "spreadsheet"
        case .code:         return "code"
        case .document:     return "document"
        case .archive:      return "zip"
        case .app:          return "app"
        case .folder:       return nil
        }
    }

    /// チップの理由「中身の多くが画像 (12 件)」。folder は nil
    func reason(count: Int) -> String? {
        switch self {
        case .image:        return String(localized: "中身の多くが画像 (\(count) 件)")
        case .video:        return String(localized: "中身の多くが動画 (\(count) 件)")
        case .audio:        return String(localized: "中身の多くが音楽 (\(count) 件)")
        case .pdf:          return String(localized: "中身の多くが PDF (\(count) 件)")
        case .presentation: return String(localized: "中身の多くがプレゼン (\(count) 件)")
        case .spreadsheet:  return String(localized: "中身の多くが表計算 (\(count) 件)")
        case .code:         return String(localized: "中身の多くがコード (\(count) 件)")
        case .document:     return String(localized: "中身の多くが書類 (\(count) 件)")
        case .archive:      return String(localized: "中身の多くが圧縮ファイル (\(count) 件)")
        case .app:          return String(localized: "中身の多くがアプリ (\(count) 件)")
        case .folder:       return nil
        }
    }

    /// UTType を列挙順で判定し、最初に当たった種類を返す。当たらなければ nil (数えない)。
    /// ソースコードは .text にも準拠するので .sourceCode を先に見る。PDF は .compositeContent にも準拠するので .pdf を先に見る
    static func classify(type: UTType?, isDirectory: Bool, isPackage: Bool) -> ContentKind? {
        if isDirectory && !isPackage { return .folder }
        guard let type else { return nil }
        if type.conforms(to: .application) { return .app }
        if type.conforms(to: .image) { return .image }
        if type.conforms(to: .movie) || type.conforms(to: .video) { return .video }
        if type.conforms(to: .audio) { return .audio }
        if type.conforms(to: .pdf) { return .pdf }
        if type.conforms(to: .presentation) { return .presentation }
        if type.conforms(to: .spreadsheet) { return .spreadsheet }
        if type.conforms(to: .sourceCode) { return .code }
        if type.conforms(to: .text) || type.conforms(to: .compositeContent) { return .document }
        if type.conforms(to: .archive) || type.conforms(to: .diskImage) { return .archive }
        return nil
    }
}

/// 代表画像 (中身の多数派が画像のときの 1 枚)。等価判定は url と更新日時 (サムネイルは比較しない)
struct RepresentativeImage: Equatable, Sendable {
    let url: URL
    let modificationDate: Date
    /// 長辺 256px 以下の PNG (チップ用)
    let thumbnailPNG: Data

    static func == (a: RepresentativeImage, b: RepresentativeImage) -> Bool {
        a.url == b.url && a.modificationDate == b.modificationDate
    }
}

struct ContentSummary: Equatable, Sendable {
    let counts: [ContentKind: Int]
    /// 最多の種類。同数は ContentKind の列挙順の先。0 件なら nil
    let dominant: ContentKind?
    /// dominant == .image のときだけ
    let representative: RepresentativeImage?

    static func dominant(of counts: [ContentKind: Int]) -> ContentKind? {
        var best: (kind: ContentKind, count: Int)?
        for kind in ContentKind.allCases {
            let count = counts[kind] ?? 0
            if count > 0, count > (best?.count ?? 0) { best = (kind, count) }
        }
        return best?.kind
    }
}

/// フォルダ直下だけを逐次読んで種類を数え、画像が多数派なら代表画像のサムネイルを作る。
/// メインの外で呼ぶ (I/O)。Task の中で呼ばれたときは cancel で途中で抜ける (best effort)
enum ContentScanner {
    static let entryLimit = 1000
    static let maxImageBytes = 20 * 1024 * 1024
    /// 代表画像にする形式 (画像パネルで選べるものと同じ)
    static let representableTypes: [UTType] = [.png, .jpeg, .heic, .gif, .webP, .tiff]
    /// Finder のカスタムアイコンの実体。隠し属性が付いていないことがあるので名前で除外する
    static let iconFileName = "Icon\r"

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey, .isPackageKey, .contentTypeKey, .contentModificationDateKey, .fileSizeKey,
    ]

    /// 読めなければ nil (存在しない、権限が無い、cancel された)
    static func scan(_ folder: URL, limit: Int = entryLimit, maxImageBytes: Int = maxImageBytes) -> ContentSummary? {
        var failed = false
        guard let enumerator = FileManager.default.enumerator(
            at: folder,
            includingPropertiesForKeys: Array(resourceKeys),
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles],
            errorHandler: { _, _ in failed = true; return false }
        ) else { return nil }

        var counts: [ContentKind: Int] = [:]
        var seen = 0
        var best: (url: URL, date: Date)?

        for case let url as URL in enumerator {
            if Task.isCancelled { return nil }
            if seen >= limit { break }
            seen += 1
            guard url.lastPathComponent != iconFileName,
                  let values = try? url.resourceValues(forKeys: resourceKeys),
                  let kind = ContentKind.classify(type: values.contentType,
                                                  isDirectory: values.isDirectory ?? false,
                                                  isPackage: values.isPackage ?? false) else { continue }
            counts[kind, default: 0] += 1

            guard kind == .image,
                  let type = values.contentType, representableTypes.contains(where: { type.conforms(to: $0) }),
                  (values.fileSize ?? Int.max) <= maxImageBytes,
                  let date = values.contentModificationDate else { continue }
            // 更新日時が新しいもの。同時刻は名前の昇順で先のもの
            if let current = best {
                if date > current.date || (date == current.date && url.lastPathComponent < current.url.lastPathComponent) {
                    best = (url, date)
                }
            } else {
                best = (url, date)
            }
        }
        if failed { return nil }

        let dominant = ContentSummary.dominant(of: counts)
        var representative: RepresentativeImage?
        if dominant == .image, let best, let png = thumbnailPNG(of: best.url) {
            representative = RepresentativeImage(url: best.url, modificationDate: best.date, thumbnailPNG: png)
        }
        return ContentSummary(counts: counts, dominant: dominant, representative: representative)
    }

    /// 画像全体を復号せず、長辺 maxPixel 以下のサムネイルを PNG で返す。EXIF の向きを反映し、キャッシュは残さない
    static func thumbnailPNG(of url: URL, maxPixel: Int = 256) -> Data? {
        let sourceOptions = [kCGImageSourceShouldCache: false] as CFDictionary
        guard let source = CGImageSourceCreateWithURL(url as CFURL, sourceOptions) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: maxPixel,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceShouldCacheImmediately: false,
        ]
        guard let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return nil }
        return NSBitmapImageRep(cgImage: cgImage).representation(using: .png, properties: [:])
    }
}
```

- [ ] **Step 6: xcodegen とテスト**

```bash
xcodegen generate
```

Run: テスト実行 (`-only-testing:FolderArtTests/ContentScannerTests -only-testing:FolderArtTests/SuggestionDictionaryTests`)
Expected: 全 PASS。`testClassifyFollowsPriorityOrder` で `.mpeg4Movie` / `.mp3` / `.swiftSource` / `.plainText` / `.zip` の判定が期待と違えば、`classify` の順ではなく **テストの UTType を疑う** (例: `.mp3` は `.audio` に準拠する。準拠しない型を使っていたらテスト側を直す)。

Run: テスト実行 (全体)
Expected: `Executed 222 tests, with 0 failures` (207 + 15)、警告 0

- [ ] **Step 7: コミット**

```bash
git add FolderArt/Services/ContentScanner.swift FolderArt/Services/SuggestionDictionary.swift FolderArt/Resources/suggestions.json FolderArt.xcodeproj/project.pbxproj FolderArtTests/ContentScannerTests.swift FolderArtTests/SuggestionDictionaryTests.swift
git commit -m "feat: ✨ ContentScanner を追加 (直下の種類を逐次数え、画像が多数派なら代表画像のサムネイルを作る)"
```

---

### Task 6: Suggestion への画像チップと SuggestionEngine の合流

**Files:**
- Modify: `FolderArt/Models/Suggestion.swift`
- Modify: `FolderArt/Services/SuggestionEngine.swift`
- Test: `FolderArtTests/SuggestionEngineTests.swift` (追加)

**Interfaces:**
- Consumes: Task 5 の `ContentSummary` / `RepresentativeImage` / `ContentKind.dictionaryKey` / `reason(count:)`、`SuggestionDictionary.entry(forKey:)`
- Produces:
  - `Suggestion.Kind.image(RepresentativeImage)`、`Suggestion.id` = `"image:<path>:<mtime>"`
  - `SuggestionEngine.suggest(for:presets:content:) -> [Suggestion]` (最大 4)。既存の `suggest(for:presets:)` は `content: nil` と同じ

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/SuggestionEngineTests.swift` に追加 (既存の `dict` / `catalog` / `engine` を使う):

```swift
    // MARK: - 中身からの合流

    private func summary(_ kind: ContentKind, count: Int, representative: RepresentativeImage? = nil) -> ContentSummary {
        ContentSummary(counts: [kind: count], dominant: kind, representative: representative)
    }

    private var sampleImage: RepresentativeImage {
        RepresentativeImage(url: URL(fileURLWithPath: "/tmp/Photos/IMG_001.jpg"),
                            modificationDate: Date(timeIntervalSince1970: 1_700_000_000), thumbnailPNG: Data([1, 2, 3]))
    }

    func testContentFillsOnlyEmptySlots() {
        // 名前で記号・絵文字が埋まっていれば、中身 (画像) では上書きしない
        let s = engine.suggest(for: "music", presets: [], content: summary(.image, count: 5))
        XCTAssertEqual(s.map(\.kind), [.symbol("music.note"), .emoji("🎵")])
    }

    func testContentAloneGivesSymbolAndEmojiWithCount() {
        let s = engine.suggest(for: "xyzzy", presets: [], content: summary(.image, count: 12))
        XCTAssertEqual(s.map(\.kind), [.symbol("photo.fill"), .emoji("📷")])
        XCTAssertTrue(s[0].reason.contains("12"), s[0].reason)
        XCTAssertEqual(s[0].reason, s[1].reason)
    }

    func testFolderDominantGivesNoContentChip() {
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: [], content: summary(.folder, count: 9)).isEmpty)
    }

    func testKindWithoutDictionaryEntryGivesNoContentChip() {
        // このテストの辞書には video の項目が無い
        XCTAssertTrue(engine.suggest(for: "xyzzy", presets: [], content: summary(.video, count: 3)).isEmpty)
    }

    func testSymbolMissingFromCatalogSkipsSymbolButKeepsEmoji() {
        let localDict = SuggestionDictionary(entries: [
            SuggestionEntry(keys: ["photo"], symbol: "not.in.catalog", emoji: "📷"),
        ])
        let localEngine = SuggestionEngine(dictionary: localDict, catalog: catalog)
        let s = localEngine.suggest(for: "xyzzy", presets: [], content: summary(.image, count: 2))
        XCTAssertEqual(s.map(\.kind), [.emoji("📷")])
    }

    func testRepresentativeImageIsAppendedLast() {
        let rep = sampleImage
        let s = engine.suggest(for: "Photos 2024", presets: [], content: summary(.image, count: 5, representative: rep))
        XCTAssertEqual(s.count, 4)
        XCTAssertEqual(s[3].kind, .image(rep))
        XCTAssertTrue(s[3].reason.contains("IMG_001.jpg"), s[3].reason)
        XCTAssertEqual(s[3].id, "image:/tmp/Photos/IMG_001.jpg:1700000000.0")
    }

    func testImageEqualityIgnoresThumbnailButNotDate() {
        let a = sampleImage
        let b = RepresentativeImage(url: a.url, modificationDate: a.modificationDate, thumbnailPNG: Data([9]))
        let c = RepresentativeImage(url: a.url, modificationDate: a.modificationDate.addingTimeInterval(1), thumbnailPNG: a.thumbnailPNG)
        XCTAssertEqual(Suggestion.Kind.image(a), .image(b))
        XCTAssertNotEqual(Suggestion.Kind.image(a), .image(c))
        XCTAssertNotEqual(Suggestion(kind: .image(a), reason: "").id, Suggestion(kind: .image(c), reason: "").id)
    }

    func testNilContentMatchesLegacyOverload() {
        for name in ["Photos 2024", "xyzzy", "Q3 reports", ""] {
            XCTAssertEqual(engine.suggest(for: name, presets: []), engine.suggest(for: name, presets: [], content: nil), name)
        }
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionEngineTests`)
Expected: コンパイルエラー (`content:` 引数と `.image` が無い)

- [ ] **Step 3: Suggestion.Kind に image を足す**

`FolderArt/Models/Suggestion.swift` 全体:

```swift
import Foundation

/// フォルダ名や中身から導いた候補 1 つ。
struct Suggestion: Equatable, Identifiable {
    enum Kind: Equatable {
        case symbol(String)
        case emoji(String)
        case text(String)
        case preset(Preset)
        /// 中身の代表画像 (等価判定は url + 更新日時。サムネイルは比較しない)
        case image(RepresentativeImage)
    }

    let kind: Kind
    /// ツールチップ用 (例: 「"photo" に一致」)
    let reason: String

    var id: String {
        switch kind {
        case .symbol(let s): return "symbol:\(s)"
        case .emoji(let s):  return "emoji:\(s)"
        case .text(let s):   return "text:\(s)"
        case .preset(let p): return "preset:\(p.id.uuidString)"
        // 同じ path の画像が更新されて再走査されたら別の id になり、チップの .task(id:) が描き直す
        case .image(let r):  return "image:\(r.url.path):\(r.modificationDate.timeIntervalSince1970)"
        }
    }
}
```

- [ ] **Step 4: SuggestionEngine に content を足す**

`FolderArt/Services/SuggestionEngine.swift`: 既存の `suggest(for:presets:)` の本体を `nameSuggestions(for:presets:)` に移し、合流を書く。既存の `suggest` を次の 2 つに置き換え、本体 (`let normalized = …` から `return [symbol, emoji, text].compactMap { $0 }` の手前まで) を `nameSuggestions` に移す:

```swift
    func suggest(for folderName: String, presets: [Preset]) -> [Suggestion] {
        suggest(for: folderName, presets: presets, content: nil)
    }

    /// 名前からの候補 (記号・絵文字・文字) を先に作り、中身の多数派で空いた枠だけ埋め、代表画像があれば末尾に足す。最大 4
    func suggest(for folderName: String, presets: [Preset], content: ContentSummary?) -> [Suggestion] {
        var (symbol, emoji, text) = nameSuggestions(for: folderName, presets: presets)

        if let content, let kind = content.dominant, let key = kind.dictionaryKey,
           let count = content.counts[kind], let reason = kind.reason(count: count) {
            let entry = dictionary.entry(forKey: key)
            if symbol == nil, let name = entry?.symbol, catalog.contains(name) {
                symbol = Suggestion(kind: .symbol(name), reason: reason)
            }
            if emoji == nil, let e = entry?.emoji {
                emoji = Suggestion(kind: .emoji(e), reason: reason)
            }
        }

        var out = [symbol, emoji, text].compactMap { $0 }
        if let rep = content?.representative {
            out.append(Suggestion(kind: .image(rep), reason: String(localized: "中身の画像「\(rep.url.lastPathComponent)」")))
        }
        return out
    }

    /// 第2段階の 4 層 (お気に入り → 辞書 → 検索語 → 規則)。枠ごとの候補を返す
    private func nameSuggestions(for folderName: String, presets: [Preset]) -> (symbol: Suggestion?, emoji: Suggestion?, text: Suggestion?) {
        let normalized = Self.normalize(folderName)
        guard !normalized.isEmpty else { return (nil, nil, nil) }
        let tokens = Self.latinTokens(normalized)

        var symbol: Suggestion?
        var emoji: Suggestion?
        var text: Suggestion?

        // …ここに既存の 1〜4 の本体をそのまま置く (変更しない)…

        return (symbol, emoji, text)
    }
```

(既存本体の `guard !normalized.isEmpty else { return [] }` は `return (nil, nil, nil)` に変える。それ以外の行は動かさない)

- [ ] **Step 5: テスト**

Run: テスト実行 (`-only-testing:FolderArtTests/SuggestionEngineTests`)
Expected: 全 PASS (既存 13 + 追加 8)

Run: テスト実行 (全体)
Expected: `Executed 230 tests, with 0 failures`、警告 0

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Models/Suggestion.swift FolderArt/Services/SuggestionEngine.swift FolderArtTests/SuggestionEngineTests.swift
git commit -m "feat: ✨ 提案に中身の多数派と代表画像を合流させる (名前の候補を優先し、空いた枠だけ埋める)"
```

---

### Task 7: AppModel の非同期走査 (generation / cancel / 注入) と提案の帯の画像チップ

**Files:**
- Modify: `FolderArt/Services/OverlayRenderer.swift:9-19` (`render(image:side:)` の公開)
- Modify: `FolderArt/Views/SuggestionStripView.swift` (全体を書き直す)
- Modify: `FolderArt/AppModel.swift` (走査、`applySuggestion` の `.image`、init の引数、deinit)
- Test: `FolderArtTests/AppModelTests.swift` (追加)

**Interfaces:**
- Consumes: Task 5 の `ContentScanner.scan` / `ContentSummary` / `RepresentativeImage`、Task 6 の `SuggestionEngine.suggest(for:presets:content:)` / `Suggestion.Kind.image`
- Produces:
  - `OverlayRenderer.render(image: NSImage, side: CGFloat) -> NSImage?`
  - `AppModel.ContentScannerFunction = @Sendable (URL) -> ContentSummary?`、`AppModel.init(history:presets:assets:suggestionEngine:contentScanner:runsMaintenance:)` (`contentScanner` の既定は `{ ContentScanner.scan($0) }`)
  - `AppModel.applySuggestion(.image(r))` → `selectImage(r.url)`

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/AppModelTests.swift` のクラス末尾に追加 (既存の `root` / `model` を使う):

```swift
    // MARK: - 中身の走査

    /// 走査の呼び出しを記録し、フォルダ名ごとに遅延と結果を差し替えられる scanner (メインの外から呼ばれる)
    private final class ScanRecorder: @unchecked Sendable {
        private let lock = NSLock()
        private var calls: [String] = []
        var delays: [String: TimeInterval] = [:]
        var results: [String: ContentSummary] = [:]

        func record(_ url: URL) -> ContentSummary? {
            lock.lock(); calls.append(url.lastPathComponent); lock.unlock()
            if let delay = delays[url.lastPathComponent] { Thread.sleep(forTimeInterval: delay) }
            return results[url.lastPathComponent] ?? ContentSummary(counts: [:], dominant: nil, representative: nil)
        }

        func count(of name: String) -> Int {
            lock.lock(); defer { lock.unlock() }
            return calls.filter { $0 == name }.count
        }
    }

    private func makeModel(scanner: ScanRecorder) -> AppModel {
        AppModel(history: HistoryStore(storageURL: root.appendingPathComponent("history2.json")),
                 presets: PresetStore(storageURL: root.appendingPathComponent("presets2.json")),
                 assets: AssetStore(directory: root.appendingPathComponent("assets2")),
                 contentScanner: { scanner.record($0) },
                 runsMaintenance: false)
    }

    /// 実際に読める PNG を 1 枚持つフォルダと、その代表画像
    private func makeFolderWithImage(_ name: String) throws -> (folder: URL, image: RepresentativeImage) {
        let folder = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let png = try XCTUnwrap(TestSupport.bitmap(of: TestSupport.makeSolidImage(size: CGSize(width: 16, height: 16), color: .red))
            .representation(using: .png, properties: [:]))
        let file = folder.appendingPathComponent("photo.png")
        try png.write(to: file)
        return (folder, RepresentativeImage(url: file, modificationDate: Date(), thumbnailPNG: png))
    }

    private func imageSummary(_ image: RepresentativeImage) -> ContentSummary {
        ContentSummary(counts: [.image: 1], dominant: .image, representative: image)
    }

    private func hasImageChip(_ m: AppModel) -> Bool {
        m.suggestions.contains { if case .image = $0.kind { return true }; return false }
    }

    func testContentScanAddsImageChipWhenFolderStaysSelected() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.results["A"] = imageSummary(image)
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        XCTAssertFalse(hasImageChip(m))   // 走査は非同期。同期の時点では名前の候補だけ
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(hasImageChip(m))
        XCTAssertTrue(m.suggestions.contains { $0.kind == .emoji("📷") })   // 中身の多数派 (画像) の絵文字も入る
        XCTAssertEqual(scanner.count(of: "A"), 1)
    }

    func testStaleScanResultIsDiscardedWhenSourceChanges() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let b = root.appendingPathComponent("B")
        try FileManager.default.createDirectory(at: b, withIntermediateDirectories: true)
        let scanner = ScanRecorder()
        scanner.delays["A"] = 0.4
        scanner.results["A"] = imageSummary(image)
        let m = makeModel(scanner: scanner)
        m.addFolders([a])   // A の走査が始まる (0.4 秒かかる)
        m.addFolders([b])   // 対象が B に変わる → A の結果は捨てられる
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertEqual(m.suggestionSourceFolder, b.standardizedFileURL)
        XCTAssertFalse(hasImageChip(m))
    }

    func testReAddingSameFolderScansAgainWithNewGeneration() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.results["A"] = imageSummary(image)
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(hasImageChip(m))
        m.folders.removeAll()
        XCTAssertTrue(m.suggestions.isEmpty)
        m.addFolders([a])
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertTrue(hasImageChip(m))
        XCTAssertEqual(scanner.count(of: "A"), 2)
    }

    func testPresetChangeReusesContentWithoutRescan() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.results["A"] = imageSummary(image)
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        try await Task.sleep(nanoseconds: 300_000_000)
        try m.presets.add(name: "星", overlay: .symbol(name: "star.fill"), settings: CompositionSettings())
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(scanner.count(of: "A"), 1)
        XCTAssertTrue(hasImageChip(m))   // 使い回した結果で候補が作り直される
    }

    func testScanResultIsDroppedWhenListBecomesEmpty() async throws {
        let (a, image) = try makeFolderWithImage("A")
        let scanner = ScanRecorder()
        scanner.delays["A"] = 0.4
        scanner.results["A"] = imageSummary(image)
        let m = makeModel(scanner: scanner)
        m.addFolders([a])
        m.folders.removeAll()   // 走査中に対象が無くなる → cancel、戻ってきても採らない
        try await Task.sleep(nanoseconds: 700_000_000)
        XCTAssertTrue(m.suggestions.isEmpty)
    }

    func testApplyingImageSuggestionCopiesIntoAssetsAndSwitchesTab() throws {
        let (_, image) = try makeFolderWithImage("A")
        model.applySuggestion(Suggestion(kind: .image(image), reason: ""))
        XCTAssertEqual(model.overlay.activeTab, .image)
        XCTAssertNotNil(model.overlay.imageAssetID)
        XCTAssertNil(model.errorMessage)
    }

    func testApplyingMissingImageSuggestionReportsError() {
        let missing = RepresentativeImage(url: root.appendingPathComponent("gone.png"), modificationDate: Date(), thumbnailPNG: Data())
        model.applySuggestion(Suggestion(kind: .image(missing), reason: ""))
        XCTAssertNotNil(model.errorMessage)
        XCTAssertNil(model.overlay.imageAssetID)
    }
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: コンパイルエラー (`contentScanner:` 引数が無い、`.image` の `switch` が網羅されていない)

- [ ] **Step 3: OverlayRenderer.render(image:side:)**

`FolderArt/Services/OverlayRenderer.swift` の `case .image(let id):` を次に変え、公開関数を足す:

```swift
        case .image(let id):
            guard let image = assets.image(for: id) else { return nil }
            return render(image: image, side: side)
```

`render(_:settings:side:assets:)` の直後に追加:

```swift
    /// 画像を配置設定に関わらず正方形に切り抜かず、長辺を side に合わせて縮小するだけに留める。
    /// 配置・アスペクト比の扱いは IconComposer 側の calculateRect (中央 fit / AspectFill / バッジ) にすべて委ねる。
    /// ここで正方形に押し込めてしまうと、余白ができたり (中央 fit・バッジ)、AspectFill + verticalOffset の
    /// パンではみ出し部分が失われてフォルダーの地色が透けて見えたりする (1.0.1 の巻き戻し)。
    /// 中身の代表画像のチップ (AssetStore に無い画像) からも使う
    static func render(image: NSImage, side: CGFloat) -> NSImage? {
        scaleToLongSide(image, side: side)
    }
```

(元の `case .image` に付いていた長いコメントはこの関数のドキュメントに移す)

- [ ] **Step 4: SuggestionStripView を書き直す**

`FolderArt/Views/SuggestionStripView.swift` 全体:

```swift
import SwiftUI

/// タブの上に出す提案の帯。高さ 36pt 固定 (候補が無くても空のまま高さを保つ)。
/// 4 つ入りきらないときは横スクロール (右へはみ出さない)
struct SuggestionStripView: View {
    let suggestions: [Suggestion]
    let assets: AssetStore
    let isApplying: Bool
    let onPick: (Suggestion) -> Void

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                if !suggestions.isEmpty {
                    Text("提案:").font(.caption).foregroundColor(.secondary)
                    ForEach(suggestions) { s in
                        // Button にしておくとキーボードと VoiceOver からも押せる
                        Button { onPick(s) } label: {
                            SuggestionChip(suggestion: s, assets: assets)
                        }
                        .buttonStyle(.plain)
                        .disabled(isApplying)
                        .opacity(isApplying ? 0.5 : 1)
                        .help(Text(s.reason))
                    }
                }
            }
            .padding(.horizontal, 4)
            .frame(height: 36)
        }
        .frame(height: 36)
    }
}

/// 候補 1 つ分のチップ (28pt のサムネイル + 短いラベル)。サムネイルは 1 回だけ描いてキャッシュ。
private struct SuggestionChip: View {
    let suggestion: Suggestion
    let assets: AssetStore
    @State private var cached: NSImage?

    var body: some View {
        HStack(spacing: 4) {
            Group {
                if let image = cached {
                    Image(nsImage: image).resizable().scaledToFit()
                } else {
                    Image(systemName: "sparkles").foregroundColor(.secondary)
                }
            }
            .frame(width: 28, height: 28)
            // 記号名やファイル名は長いことがあるので幅を抑えて中央を省略する
            Text(label).font(.caption).lineLimit(1).truncationMode(.middle).frame(maxWidth: 120)
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.accentColor.opacity(0.12)))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Color.accentColor.opacity(0.35)))
        .task(id: suggestion.id) { cached = thumbnail }
    }

    private var label: String {
        switch suggestion.kind {
        case .symbol(let s): return s
        case .emoji(let e):  return e
        case .text(let t):   return t
        case .preset(let p): return p.name
        case .image(let r):  return r.url.lastPathComponent
        }
    }

    /// 他のチップと同じ「フォルダに合成した見た目」。画像チップは走査で作ったサムネイル PNG から描く (AssetStore には無い)
    private var thumbnail: NSImage? {
        let settings: CompositionSettings
        let rendered: NSImage?
        let fills: Bool
        switch suggestion.kind {
        case .symbol(let s):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.symbol(name: s), settings: settings, side: 128, assets: assets)
        case .emoji(let e):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.emoji(e), settings: settings, side: 128, assets: assets)
        case .text(let t):
            settings = CompositionSettings(); fills = false
            rendered = OverlayRenderer.render(.text(t), settings: settings, side: 128, assets: assets)
        case .preset(let p):
            settings = p.settings; fills = p.overlay.fillsFolderWhenClipped
            rendered = OverlayRenderer.render(p.overlay, settings: settings, side: 128, assets: assets)
        case .image(let r):
            settings = CompositionSettings(); fills = true
            rendered = NSImage(data: r.thumbnailPNG).flatMap { OverlayRenderer.render(image: $0, side: 128) }
        }
        guard let rendered else { return nil }
        return IconComposer.compose(overlay: rendered, settings: settings, fillsWhenClipped: fills)
    }
}
```

- [ ] **Step 5: AppModel**

`FolderArt/AppModel.swift`:

(a) プロパティ (`private let suggestionEngine: SuggestionEngine` の直後に追加):

```swift
    /// 中身の走査 (テストで差し替える)。メインの外で呼ばれる
    typealias ContentScannerFunction = @Sendable (URL) -> ContentSummary?
    private let scanContents: ContentScannerFunction
    /// 最後に走査したフォルダとその結果 (summary nil = 読めなかった)。対象が変わるまで使い回す
    private var contentSummary: (folder: URL, summary: ContentSummary?)?
    private var contentScanTask: Task<Void, Never>?
    /// 走査の世代。戻ってきた結果がこれと違えば捨てる (同じ URL を外して入れ直した場合も新しい世代だけ採る)
    private var scanGeneration = 0
    private var scanningFolder: URL?
```

(b) init の引数 (`suggestionEngine:` の次に追加) と代入:

```swift
    init(history: HistoryStore = HistoryStore(),
         presets: PresetStore = PresetStore(),
         assets: AssetStore = AssetStore(),
         suggestionEngine: SuggestionEngine = SuggestionEngine(dictionary: SuggestionDictionary.load(), catalog: SymbolCatalog.shared),
         contentScanner: @escaping ContentScannerFunction = { ContentScanner.scan($0) },
         runsMaintenance: Bool = true) {
        self.history = history
        self.presets = presets
        self.assets = assets
        self.suggestionEngine = suggestionEngine
        self.scanContents = contentScanner
```

(c) `refreshSuggestions` を置き換え、走査の 2 関数を足す:

```swift
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
            await MainActor.run {
                guard let self, self.scanGeneration == generation, self.suggestionSourceFolder == folder else { return }
                self.contentSummary = (folder, summary)
                self.scanningFolder = nil
                self.contentScanTask = nil
                self.refreshSuggestions(folders: self.folders.folders, selectedIDs: self.folders.selectedIDs,
                                        presets: self.presets.presets)
            }
        }
    }
```

(d) `applySuggestion` の `switch` に追加:

```swift
        case .image(let r):     selectImage(r.url)
```

(e) `deinit` の先頭に `contentScanTask?.cancel()` を足す。

`suggestions` のドキュメントコメントを「提案 (フォルダ名と中身から)。空なら帯はチップ無しで高さだけ保つ」に直す。

- [ ] **Step 6: テスト**

Run: テスト実行 (`-only-testing:FolderArtTests/AppModelTests`)
Expected: 全 PASS (追加 7 件)。時間待ちのテストは 0.3 / 0.7 秒。遅い Mac で落ちるなら待ち時間を 2 倍にする (走査側の遅延は変えない)。

Run: テスト実行 (全体)
Expected: `Executed 237 tests, with 0 failures`、警告 0

実機 (Task 4 と同じ手順でビルドして起動): 画像の多いフォルダを落とすと提案の帯に「提案: 📷 photo.fill 📷 ファイル名」のように最大 4 つ出て、画像チップを押すと画像タブに入る。記号名の長いチップが省略される。書類だけのフォルダでは記号・絵文字だけ。サブフォルダだらけのフォルダでは名前の候補だけ。

- [ ] **Step 7: コミット**

```bash
git add FolderArt/Services/OverlayRenderer.swift FolderArt/Views/SuggestionStripView.swift FolderArt/AppModel.swift FolderArtTests/AppModelTests.swift
git commit -m "feat: ✨ フォルダの中身を非同期に走査して提案に足す (世代で古い結果を捨てる、画像チップ、帯の横スクロール)"
```

---

### Task 8: 言語メニュー (AppLanguage / LanguageSetting、「表示 > 言語」、再起動アラート)

**Files:**
- Create: `FolderArt/Services/AppLanguage.swift`
- Modify: `FolderArt/FolderArtApp.swift`
- Modify: `FolderArt/ContentView.swift` (`@EnvironmentObject`、`toolbar` にアラート)
- Test: `FolderArtTests/LanguageSettingTests.swift`

**Interfaces:**
- Consumes: Task 2 のカタログ (「言語」「システムに従う」「言語の変更」「再起動」「あとで」「再起動できませんでした: %@」とアラート本文)
- Produces:
  - `enum AppLanguage: String, CaseIterable, Identifiable { case system, ja, en, de, es, fr, ko, ptBR = "pt-BR", zhHant = "zh-Hant"; var displayName: String }`
  - `@MainActor final class LanguageSetting: ObservableObject { static let key = "FolderArtLanguage"; static let appleLanguagesKey = "AppleLanguages"; @Published var selection: AppLanguage; @Published var needsRelaunch: Bool; init(defaults: UserDefaults = .standard); func relaunch(onFailure: @escaping (Error) -> Void) }`

- [ ] **Step 1: 失敗するテストを書く**

`FolderArtTests/LanguageSettingTests.swift`:

```swift
import XCTest
@testable import FolderArt

/// UserDefaults の suite を注入する。suite の検索リストには NSGlobalDomain も入るので、
/// 「消えたこと」は object(forKey:) ではなく persistentDomain (suite 自身の中身) で確かめる
@MainActor
final class LanguageSettingTests: XCTestCase {
    private var suiteName: String!
    private var defaults: UserDefaults!

    override func setUp() async throws {
        suiteName = "LanguageSettingTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suiteName)
    }

    private var stored: [String: Any] { defaults.persistentDomain(forName: suiteName) ?? [:] }

    func testDefaultIsSystemEvenWhenAppleLanguagesExists() {
        defaults.set(["fr"], forKey: LanguageSetting.appleLanguagesKey)   // 自前キーが無ければシステム扱い
        let setting = LanguageSetting(defaults: defaults)
        XCTAssertEqual(setting.selection, .system)
        XCTAssertFalse(setting.needsRelaunch)
    }

    func testSelectingLanguageWritesBothKeysAndFlagsRelaunch() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .en
        XCTAssertEqual(stored[LanguageSetting.key] as? String, "en")
        XCTAssertEqual(stored[LanguageSetting.appleLanguagesKey] as? [String], ["en"])
        XCTAssertTrue(setting.needsRelaunch)

        setting.needsRelaunch = false
        setting.selection = .zhHant
        XCTAssertEqual(stored[LanguageSetting.appleLanguagesKey] as? [String], ["zh-Hant"])
        XCTAssertTrue(setting.needsRelaunch)
    }

    func testSystemRemovesBothKeys() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .ja
        setting.selection = .system
        XCTAssertNil(stored[LanguageSetting.key])
        XCTAssertNil(stored[LanguageSetting.appleLanguagesKey])
        XCTAssertTrue(setting.needsRelaunch)
    }

    func testRestoredFromOwnKey() {
        defaults.set("pt-BR", forKey: LanguageSetting.key)
        XCTAssertEqual(LanguageSetting(defaults: defaults).selection, .ptBR)
    }

    func testUnknownStoredValueFallsBackToSystem() {
        defaults.set("xx-YY", forKey: LanguageSetting.key)
        XCTAssertEqual(LanguageSetting(defaults: defaults).selection, .system)
    }

    func testReselectingSameValueDoesNotFlagRelaunch() {
        let setting = LanguageSetting(defaults: defaults)
        setting.selection = .en
        setting.needsRelaunch = false
        setting.selection = .en
        XCTAssertFalse(setting.needsRelaunch)
    }

    func testNineChoicesWithDistinctNamesAndCodes() {
        XCTAssertEqual(AppLanguage.allCases.count, 9)
        XCTAssertEqual(AppLanguage.allCases.first, .system)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.displayName)).count, 9)
        XCTAssertEqual(Set(AppLanguage.allCases.map(\.rawValue)), ["system", "ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"])
    }
}
```

- [ ] **Step 2: 失敗を確認する**

Run: テスト実行 (`-only-testing:FolderArtTests/LanguageSettingTests`)
Expected: コンパイルエラー

- [ ] **Step 3: AppLanguage / LanguageSetting を書く**

`FolderArt/Services/AppLanguage.swift`:

```swift
import AppKit
import Combine

/// アプリ内の言語メニューの選択肢。rawValue は AppleLanguages に書く言語コード (String Catalog の言語と同じ)
enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case ja, en, de, es, fr, ko
    case ptBR = "pt-BR"
    case zhHant = "zh-Hant"

    var id: String { rawValue }

    /// メニューの表示名。system だけ訳し、他は各言語の自称 (どの言語で起動していても同じ見た目)
    var displayName: String {
        switch self {
        case .system: return String(localized: "システムに従う")
        case .ja:     return "日本語"
        case .en:     return "English"
        case .de:     return "Deutsch"
        case .es:     return "Español"
        case .fr:     return "Français"
        case .ko:     return "한국어"
        case .ptBR:   return "Português (Brasil)"
        case .zhHant: return "繁體中文"
        }
    }
}

/// 言語の選択を UserDefaults に保存し、再起動を促す。macOS は起動中の言語切り替えを持たないので
/// AppleLanguages を書いて次回起動 (または今すぐの再起動) で反映する。
/// 起動時は自前キーだけ読む (AppleLanguages は上書きしていなくてもシステムの値が読めてしまい、
/// 「システムに従う」と区別できないため)
@MainActor
final class LanguageSetting: ObservableObject {
    static let key = "FolderArtLanguage"
    static let appleLanguagesKey = "AppleLanguages"

    @Published var selection: AppLanguage {
        didSet {
            guard selection != oldValue else { return }
            persist()
            needsRelaunch = true
        }
    }
    /// 変更後のアラート表示用。閉じれば false に戻る (再提示はしない。設定は保存済みなので次回起動で反映される)
    @Published var needsRelaunch = false

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.selection = defaults.string(forKey: Self.key).flatMap(AppLanguage.init(rawValue:)) ?? .system
    }

    /// UserDefaults は cfprefsd を介するので、set した値は plist への書き出しを待たずに新しいプロセスから読める
    private func persist() {
        if selection == .system {
            defaults.removeObject(forKey: Self.key)
            defaults.removeObject(forKey: Self.appleLanguagesKey)
        } else {
            defaults.set(selection.rawValue, forKey: Self.key)
            defaults.set([selection.rawValue], forKey: Self.appleLanguagesKey)
        }
    }

    /// 自分をもう 1 つ起動してから終了する。起動に失敗したら終了せず onFailure に渡す
    func relaunch(onFailure: @escaping (Error) -> Void) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration) { _, error in
            DispatchQueue.main.async {
                if let error {
                    onFailure(error)
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
}
```

- [ ] **Step 4: メニューとアラート**

`FolderArt/FolderArtApp.swift` 全体:

```swift
import SwiftUI

@main
struct FolderArtApp: App {
    @StateObject private var language = LanguageSetting()

    var body: some Scene {
        // WindowGroup だと新規ウィンドウごとに別の AppModel が生成され、同じ資産ディレクトリを
        // 共有するため、後から開いたウィンドウの reapAssets() が先のウィンドウでまだ参照されて
        // いない画像を回収してしまう。単一ウィンドウに限定してこれを防ぐ
        Window("FolderArt", id: "main") {
            ContentView()
                .environmentObject(language)
        }
        .windowStyle(.titleBar)
        .windowResizability(.contentMinSize)
        .defaultSize(width: 760, height: 780)
        .commands {
            CommandGroup(after: .importExport) {
                Button("お気に入りのパックを書き出す…") {
                    NotificationCenter.default.post(name: AppModel.exportPackNotification, object: nil)
                }
                Button("お気に入りのパックを読み込む…") {
                    NotificationCenter.default.post(name: AppModel.importPackNotification, object: nil)
                }
            }
            // 「表示」メニューに「言語」サブメニュー (チェックマーク付きの 9 択)。選ぶと ContentView がアラートで再起動を促す
            CommandGroup(after: .toolbar) {
                Picker("言語", selection: $language.selection) {
                    ForEach(AppLanguage.allCases) { lang in
                        Text(lang.displayName).tag(lang)
                    }
                }
            }
        }
    }
}
```

`FolderArt/ContentView.swift`: `@StateObject private var model = AppModel()` の直後に追加:

```swift
    @EnvironmentObject private var language: LanguageSetting
```

`toolbar` を次に置き換える (既存の `.alert("お知らせ")` は `body` 側に残す。同じビューに 2 つの `.alert` を付けないよう、言語のアラートはツールバーに付ける):

```swift
    private var toolbar: some View {
        HStack {
            Text("FolderArt").font(.headline)
            Spacer()
            Button { showHistory = true } label: { Label("履歴", systemImage: "clock") }
                .buttonStyle(.borderless)
                .disabled(model.isApplying)
        }
        .padding(.horizontal).padding(.vertical, 10)
        // 適用中は [再起動] を出さない (終了すると適用が途中で止まる)。設定は保存済みなので次回起動で反映される
        .alert("言語の変更", isPresented: $language.needsRelaunch) {
            if !model.isApplying {
                Button("再起動") {
                    language.relaunch { error in
                        model.errorMessage = String(localized: "再起動できませんでした: \(error.localizedDescription)")
                    }
                }
            }
            Button("あとで", role: .cancel) {}
        } message: {
            Text("言語の変更は次回起動時に反映されます。今すぐ再起動しますか？ (フォルダーのリストと今の入力は消えます)")
        }
    }
```

- [ ] **Step 5: xcodegen、--check、テスト**

```bash
xcodegen generate
python3 scripts/localization/build-xcstrings.py --check
```

Expected: `missing: 0`

Run: テスト実行 (`-only-testing:FolderArtTests/LanguageSettingTests`)
Expected: 7 tests PASS

Run: テスト実行 (全体)
Expected: `Executed 244 tests, with 0 failures`、警告 0

実機: 「表示 > 言語」に 9 項目、English を選ぶとアラート → [再起動] で英語で立ち上がる (メニュー、ボタン、設定のラベル、履歴シート)。「システムに従う」で日本語に戻る。適用中に言語を変えると [あとで] だけが出る。

- [ ] **Step 6: コミット**

```bash
git add FolderArt/Services/AppLanguage.swift FolderArt/FolderArtApp.swift FolderArt/ContentView.swift FolderArt.xcodeproj/project.pbxproj FolderArtTests/LanguageSettingTests.swift
git commit -m "feat: ✨ 「表示 > 言語」メニューで 8 言語を切り替えられるようにする (AppleLanguages に保存して再起動を促す)"
```

---

### Task 9: バージョン、README (機能一覧・構成・メイン画像)、最終確認 — コントローラー (親セッション) が実施

**Files:**
- Modify: `project.yml` (`MARKETING_VERSION: 1.4.0`, `CURRENT_PROJECT_VERSION: 7`)
- Modify: `README.md`
- Create: `docs/images/main.png` (実機で撮影。画面収録の権限は親セッションにしかないので、このタスク全体を親セッションが行い、README の参照先変更と画像を同じコミットに入れる)

- [ ] **Step 1: バージョン**

`project.yml`: `MARKETING_VERSION: 1.4.0`、`CURRENT_PROJECT_VERSION: 7`。`xcodegen generate`。

- [ ] **Step 2: README**

機能一覧の「フォルダ名からの自動提案」の行を次に置き換える:

```
- フォルダ名と中身からの自動提案: 記号・絵文字・文字・お気に入りの候補をタブの上に最大 4 つ表示。直下のファイルの種類 (画像・動画・書類など) に合う記号・絵文字と、画像が多ければ代表画像 — Suggestions from the folder name and contents: up to four symbol / emoji / text / preset candidates above the tabs, plus a symbol / emoji for the dominant file kind and a representative image when images dominate
```

「記号と文字の色を指定」の行の直後に追加:

```
- 文字のフォントと太さ: macOS 同梱の 8 種のフォントと 6 段階の太さ (太さは記号にも効く) — Font and weight for text: eight fonts bundled with macOS and six weights (weight also applies to symbols)
```

機能一覧の末尾に追加:

```
- 8 言語対応 (日本語・英語・ドイツ語・スペイン語・フランス語・韓国語・ポルトガル語 (ブラジル)・繁体字中国語) と「表示 > 言語」メニュー — Eight languages (Japanese, English, German, Spanish, French, Korean, Brazilian Portuguese, Traditional Chinese) and a View > Language menu
```

スクリーンショットの行を `<img width="760" alt="FolderArt 1.4.0" src="docs/images/main.png" />` に。

「使い方」3 を次に置き換える:

```
3. **設定を調整** — 配置・大きさ・不透明度・上下位置、記号と文字は色と太さ、文字はフォントも。
   **フォルダー形に切り抜く** を ON にすると、はみ出した部分をフォルダーの形で切り落とす
   Adjust position, size, opacity, vertical offset, tint and weight (symbols and text), and font (text).
   Turn on "clip to folder shape" to trim the overlay to the folder outline
```

「使い方」の末尾に追加:

```
9. **言語** — メニューバーの「表示 > 言語」から 8 言語を選べる (再起動で反映)
   Language: pick one of eight languages from View > Language in the menu bar (takes effect after a restart)
```

「プロジェクト構成」に追加 (既存の並びに合わせてアルファベット順に):

```
│   ├── AppLanguage.swift       # 言語メニューの選択と AppleLanguages への保存
│   ├── ContentScanner.swift    # フォルダ直下の種類と代表画像
│   ├── FontCatalog.swift       # 厳選フォントと家族 + 太さの解決
```

`Resources/` に:

```
│   ├── InfoPlist.xcstrings     # 書類の種類名 (8 言語、生成物)
│   ├── Localizable.xcstrings   # UI の文言 (8 言語、生成物)
```

構成図の末尾 (FolderArt/ の外) に:

```
scripts/localization/
├── strings.json                # 文言の元 (キー → 8 言語)
└── build-xcstrings.py          # .xcstrings の生成と、ソースとの突き合わせ (--check)
```

「技術詳細」に 1 行: `- **String Catalog** による 8 言語対応 (`scripts/localization/strings.json` から生成)`。

- [ ] **Step 3: スクリーンショット**

Release ビルドを起動し、フォルダ 3 件 (うち 1 つは画像の多い「Photos」)、文字タブでフォントと太さの Picker が見える状態、提案の帯にチップ 4 つ (画像チップを含む)、お気に入りのチップ 2 つ、プレビュー表示の状態で `screencapture -x -o -l <CGWindowID>` により Retina 2x で撮り、`docs/images/main.png` に保存してコミットする。

- [ ] **Step 4: 全テストとビルド、--check**

```bash
python3 scripts/localization/build-xcstrings.py --check
```

Run: テスト実行 (全体)
Expected: `Executed 244 tests, with 0 failures`、プロジェクト由来の警告 0、`missing: 0`

- [ ] **Step 5: コミット**

```bash
git add project.yml FolderArt.xcodeproj/project.pbxproj README.md docs/images/main.png
git commit -m "chore: 🔖 1.4.0 に更新し README の機能一覧・構成・メイン画像を更新"
```

- [ ] **Step 6: 仕上げ (コントローラー)**

実機確認 (フォント・太さの切り替えとプレビュー、他タブでの無効表示、言語メニューで English → 再起動 → 英語の UI、「システムに従う」で日本語に戻る、画像の多いフォルダで画像チップ → 画像タブ、4 チップが帯に収まる、1.3.0 で作ったお気に入り・パックが同じ見た目) → `docs/images/main.png` の撮影とコミット → Codex CLI (`@codex-rescue`、フォアグラウンド) で事前レビュー → PR (日英併記) → Codex レビュー対応 (指摘が尽きるまで) → `develop` にマージ → `main` を同期 → v1.4.0 リリース → `/Users/annrie/アプリケーション/FolderArt.app` を入れ替え。
