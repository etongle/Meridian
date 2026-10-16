#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
DEST="$PROJECT_DIR/.build/Sparkle"
ARCHIVE="$PROJECT_DIR/.build/Sparkle-2.10.0.tar.xz"
if [[ -d "$DEST/Sparkle.framework" ]]; then exit 0; fi
mkdir -p "$DEST"
curl -fL --retry 2 --proto '=https' --tlsv1.2 \
  'https://github.com/sparkle-project/Sparkle/releases/download/2.10.0/Sparkle-2.10.0.tar.xz' -o "$ARCHIVE"
print 'c2bf58aa8387266ac179357b1415d6f2635f044da8be41042af32425dae6da0c  '"$ARCHIVE" | shasum -a 256 --check
tar -xf "$ARCHIVE" -C "$DEST"
