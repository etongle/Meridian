#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h:h}"
if [[ -f "$PROJECT_DIR/.build/AppIcon.icns" && "$PROJECT_DIR/.build/AppIcon.icns" -nt "$PROJECT_DIR/Resources/AppIcon.png" ]]; then exit 0; fi
ICONSET="$PROJECT_DIR/.build/Meridian.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$PROJECT_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$PROJECT_DIR/Resources/AppIcon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$PROJECT_DIR/.build/AppIcon.icns"
