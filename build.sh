#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="$PROJECT_DIR/.build"
APP_DIR="${1:-$PROJECT_DIR/dist/Meridian.app}"
IDENTITY="${MERIDIAN_SIGN_IDENTITY:--}"
zsh "$PROJECT_DIR/scripts/fetch-sparkle.sh"
zsh "$PROJECT_DIR/scripts/build-icon.sh"
mkdir -p "$BUILD_DIR/ModuleCache" "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Frameworks" "$APP_DIR/Contents/Resources"
MERIDIAN_ARCHITECTURES=(${=MERIDIAN_ARCHS:-arm64})
for TARGET_ARCH in $MERIDIAN_ARCHITECTURES; do
  swiftc -O -swift-version 5 -parse-as-library -target "$TARGET_ARCH-apple-macos14.0" \
    -module-cache-path "$BUILD_DIR/ModuleCache" -F "$BUILD_DIR/Sparkle" \
    -Xlinker -rpath -Xlinker '@executable_path/../Frameworks' \
    "$PROJECT_DIR"/Sources/*.swift -o "$BUILD_DIR/Meridian-$TARGET_ARCH" \
    -framework AppKit -framework SwiftUI -framework Combine -framework Sparkle
done
if (( ${#MERIDIAN_ARCHITECTURES} == 1 )); then
  cp "$BUILD_DIR/Meridian-${MERIDIAN_ARCHITECTURES[1]}" "$APP_DIR/Contents/MacOS/Meridian"
else
  BINARIES=()
  for TARGET_ARCH in $MERIDIAN_ARCHITECTURES; do BINARIES+=("$BUILD_DIR/Meridian-$TARGET_ARCH"); done
  lipo -create $BINARIES -output "$APP_DIR/Contents/MacOS/Meridian"
fi
ditto "$BUILD_DIR/Sparkle/Sparkle.framework" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
cp "$PROJECT_DIR/ThirdParty/Sparkle-LICENSE.txt" "$APP_DIR/Contents/Resources/Sparkle-LICENSE.txt"
cp "$PROJECT_DIR/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
cp "$PROJECT_DIR/NOTICE" "$APP_DIR/Contents/Resources/NOTICE"
cp "$PROJECT_DIR/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
cp "$PROJECT_DIR/.build/AppIcon.icns" "$APP_DIR/Contents/Resources/AppIcon.icns"
cp "$PROJECT_DIR/Resources/AppIcon.png" "$APP_DIR/Contents/Resources/StatusIcon.png"
python3 "$PROJECT_DIR/scripts/write-info.py" "$PROJECT_DIR/Config/release.json" "$APP_DIR/Contents/Info.plist"
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework/Versions/B/Autoupdate"
while IFS= read -r BUNDLE; do
  codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$BUNDLE"
done < <(find "$APP_DIR/Contents/Frameworks/Sparkle.framework" -depth \( -name '*.xpc' -o -name '*.app' \) -print)
codesign --force --options runtime --timestamp=none --sign "$IDENTITY" "$APP_DIR/Contents/Frameworks/Sparkle.framework"
if [[ "$IDENTITY" == '-' ]]; then
  codesign --force --sign - "$APP_DIR"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP_DIR"
fi
codesign --verify --deep --strict "$APP_DIR"
print "Built: $APP_DIR"
