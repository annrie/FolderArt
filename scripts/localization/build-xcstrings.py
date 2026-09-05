#!/usr/bin/env python3
"""strings.json / infoplist.json から String Catalog (.xcstrings) を生成する。

    python3 scripts/localization/build-xcstrings.py          # 生成
    python3 scripts/localization/build-xcstrings.py --check  # ソースの文言との突き合わせ (欠けがあれば exit 1)

strings.json の形: {"キー": ["ja", "en", "de", "es", "fr", "ko", "pt-BR", "zh-Hant"], ...}
値に "one||other" と書くと単数・複数の variation になる。"\n" は改行。
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
    # リテラル中の "%" はそのまま残す (キー側の "%%" と "%lld" が両方 "%" に正規化されるので、"上\(n)%" は "上%%" になり "上%lld%%" と一致する)
    return "".join(out)


def source_literals():
    """FolderArt/ 配下の Swift から、日本語を含む文字列リテラル (コメント行を除く) を集める"""
    found = {}
    for dirpath, _, filenames in os.walk(os.path.join(ROOT, "FolderArt")):
        for fn in filenames:
            if not fn.endswith(".swift"):
                continue
            path = os.path.join(dirpath, fn)
            in_multiline = False
            with open(path, encoding="utf-8") as f:
                for lineno, line in enumerate(f, 1):
                    # 複数行文字列 (""") の中身は読み飛ばす (UI 文言は複数行リテラルを使わない。
                    # JSON テンプレートなどの中身をここで日本語リテラルとして拾わないようにする。
                    # 実物照合は --stringsdata のコンパイラ抽出が正確に行う)
                    if in_multiline:
                        if '"""' in line:
                            in_multiline = False
                        continue
                    if '"""' in line:
                        in_multiline = line.count('"""') % 2 == 1
                        continue
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
