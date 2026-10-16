#!/bin/zsh
set -euo pipefail
PROJECT_DIR="${0:A:h}"
BUILD_DIR="${WORLD_CLOCK_BUILD_DIR:-$PROJECT_DIR/.build}"
mkdir -p "$BUILD_DIR/ModuleCache"
python3 "$PROJECT_DIR/scripts/generate-world-regions.py" --check
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$PROJECT_DIR/Sources/Localization.swift" \
  "$PROJECT_DIR/Sources/DropdownGeometry.swift" \
  "$PROJECT_DIR/Sources/DesktopGeometry.swift" \
  "$PROJECT_DIR/Sources/UpdateConfiguration.swift" \
  "$PROJECT_DIR/Sources/ClockModel.swift" \
  "$PROJECT_DIR/Sources/WorldRegions.swift" \
  "$PROJECT_DIR/Sources/WorldRegionData.swift" \
  "$PROJECT_DIR/Sources/Weather.swift" \
  "$PROJECT_DIR/Tests/ClockModelTests.swift" \
  -o "$BUILD_DIR/ClockModelTests"
"$BUILD_DIR/ClockModelTests"
swiftc -swift-version 5 -parse-as-library \
  -module-cache-path "$BUILD_DIR/ModuleCache" \
  "$PROJECT_DIR/Sources/SingleInstance.swift" "$PROJECT_DIR/Tests/SingleInstanceProbe.swift" \
  -o "$BUILD_DIR/SingleInstanceProbe"
python3 "$PROJECT_DIR/Tests/single-instance.py" "$BUILD_DIR/SingleInstanceProbe"
