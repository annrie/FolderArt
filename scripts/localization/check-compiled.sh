#!/bin/bash
# SWIFT_EMIT_LOC_STRINGS=YES で一時 DerivedData にビルドし、コンパイラが抽出した文言のキーと strings.json を厳密に突き合わせる。
# PR の前に 1 回走らせる (通常の --check は正規表現の簡易版)。ビルドが失敗したらその終了コードで止まり、error: 行を全部出す。
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d /tmp/folderart-loc.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
set +e
xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$tmp" SWIFT_EMIT_LOC_STRINGS=YES > "$tmp/build.log" 2>&1
status=$?
set -e
grep -E "error:|BUILD (SUCCEEDED|FAILED)" "$tmp/build.log" | grep -v "ld: warning" || true
if [ "$status" -ne 0 ]; then
  echo "xcodebuild failed (exit $status); see the error: lines above" >&2
  exit "$status"
fi
python3 scripts/localization/build-xcstrings.py --stringsdata "$tmp"
