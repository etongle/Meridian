#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
cd "$PROJECT_DIR"
VERSION=$(python3 -c 'import json; print(json.load(open("Config/release.json"))["version"])')
PUBLIC_KEY=$(python3 -c 'import json; print(json.load(open("Config/release.json"))["sparklePublicKey"])')
TAG="v$VERSION"
REPOSITORY=$(python3 -c 'import json; print(json.load(open("Config/release.json"))["repository"])')
ARCHIVE="Meridian-$VERSION-macOS.zip"
UPDATES="$PROJECT_DIR/dist/updates"
mkdir -p "$UPDATES"
test -n "$PUBLIC_KEY" || { print -u2 'Configure a stable Sparkle public key first.'; exit 1; }
codesign --verify --deep --strict dist/Meridian.app
ditto -c -k --sequesterRsrc --keepParent dist/Meridian.app "$UPDATES/$ARCHIVE"
NOTES="$PROJECT_DIR/releases/$TAG.md"
[[ -f "$NOTES" ]] || NOTES="$PROJECT_DIR/CHANGELOG.md"
cp "$NOTES" "$UPDATES/Meridian-$VERSION-macOS.md"
if [[ -n "${SPARKLE_PRIVATE_KEY:-}" ]]; then
  printf '%s' "$SPARKLE_PRIVATE_KEY" | .build/Sparkle/bin/generate_appcast --ed-key-file - --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" "$UPDATES"
else
  .build/Sparkle/bin/generate_appcast --account "${MERIDIAN_SPARKLE_ACCOUNT:-etongle.Meridian}" --maximum-deltas 0 --embed-release-notes --download-url-prefix "https://github.com/$REPOSITORY/releases/download/$TAG/" "$UPDATES"
fi
swift -module-cache-path .build/ModuleCache scripts/verify-appcast.swift "$UPDATES/appcast.xml" "$UPDATES/$ARCHIVE" "$PUBLIC_KEY"
cp LICENSE NOTICE THIRD_PARTY_NOTICES.md "$UPDATES/"
cp "$NOTES" "$UPDATES/RELEASE_NOTES.md"
cd "$UPDATES"
shasum -a 256 "$ARCHIVE" appcast.xml LICENSE NOTICE THIRD_PARTY_NOTICES.md RELEASE_NOTES.md > SHA256SUMS
print "Signed release: $UPDATES"
