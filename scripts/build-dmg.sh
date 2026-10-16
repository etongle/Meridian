#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
VERSION=$(python3 -c 'import json; print(json.load(open("Config/release.json"))["version"])')
OUTPUT="$PROJECT_DIR/dist/updates/Meridian-$VERSION-macOS.dmg"
mkdir -p "$PROJECT_DIR/.build" "$PROJECT_DIR/dist/updates"
STAGING=$(mktemp -d "$PROJECT_DIR/.build/dmg-staging.XXXXXX")
trap 'rm -rf "$STAGING"' EXIT
ditto dist/Meridian.app "$STAGING/Meridian.app"
ln -s /Applications "$STAGING/Applications"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$STAGING/"
cat > "$STAGING/Read Me.txt" <<'TXT'
Meridian — Your world. At a glance.

Drag Meridian.app to Applications, then open it from Applications.
Requires macOS 14 or later. Universal for Apple Silicon and Intel.
This release is not Apple-notarized; macOS may block first launch.

Noncommercial use only. See LICENSE, NOTICE and THIRD_PARTY_NOTICES.md.

将 Meridian.app 拖入 Applications（应用程序），然后从“应用程序”打开。
需要 macOS 14 或更新版本，支持 Apple Silicon 和 Intel。
此版本尚未经过 Apple 公证。仅限非商业使用，详见 LICENSE。

https://github.com/etongle/Meridian
TXT
hdiutil create -volname Meridian -srcfolder "$STAGING" -fs HFS+ -format UDZO -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
print "Built DMG: $OUTPUT"
