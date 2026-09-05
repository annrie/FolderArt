#!/bin/bash
# SWIFT_EMIT_LOC_STRINGS=YES で一時 DerivedData にビルドし、コンパイラが抽出した文言のキーと strings.json を厳密に突き合わせる。
# PR の前に 1 回走らせる (通常の --check は正規表現の簡易版)。
set -euo pipefail
cd "$(dirname "$0")/../.."
tmp=$(mktemp -d /tmp/folderart-loc.XXXXXX)
trap 'rm -rf "$tmp"' EXIT
xcodebuild build -project FolderArt.xcodeproj -scheme FolderArt -configuration Debug -destination 'platform=macOS' \
  -derivedDataPath "$tmp" SWIFT_EMIT_LOC_STRINGS=YES 2>&1 | grep -E "error:|BUILD (SUCCEEDED|FAILED)" | tail -1
python3 scripts/localization/build-xcstrings.py --stringsdata "$tmp"
