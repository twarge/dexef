#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CONFIGURATION="${CONFIGURATION:-debug}"
BUILD_DIR="${BUILD_DIR:-$ROOT_DIR/build}"
DERIVED_DATA_PATH="${DERIVED_DATA_PATH:-$BUILD_DIR/xcode}"
APP_DIR="${APP_DIR:-$ROOT_DIR/dist/DeXeF.app}"
PROJECT="$ROOT_DIR/DeXeF.xcodeproj"
SCHEME="DeXeF"

case "$CONFIGURATION" in
	debug|Debug)
		XCODE_CONFIGURATION="Debug"
		;;
	release|Release)
		XCODE_CONFIGURATION="Release"
		;;
	*)
		echo "usage: CONFIGURATION=[debug|release] $0" >&2
		exit 64
		;;
esac

cd "$ROOT_DIR"
mkdir -p "$BUILD_DIR/swift-module-cache"

# Regenerate the app/document icons into DeXeF/Assets.xcassets before building.
# The catalog is compiled into the app by xcodebuild, so there is no separate
# .icns to produce.
swift -module-cache-path "$BUILD_DIR/swift-module-cache" Scripts/GenerateBlueprintIcons.swift

xcodebuild \
	-project "$PROJECT" \
	-scheme "$SCHEME" \
	-configuration "$XCODE_CONFIGURATION" \
	-destination "generic/platform=macOS" \
	-derivedDataPath "$DERIVED_DATA_PATH" \
	build

BUILT_APP="$DERIVED_DATA_PATH/Build/Products/$XCODE_CONFIGURATION/DeXeF.app"
[[ -d "$BUILT_APP" ]] || {
	echo "error: built app not found: $BUILT_APP" >&2
	exit 1
}

rm -rf "$APP_DIR"
mkdir -p "$(dirname "$APP_DIR")"
ditto "$BUILT_APP" "$APP_DIR"

echo "$APP_DIR"
