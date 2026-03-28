#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/MacScheme"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacScheme.app"
DEST_APP="$DIST_DIR/$APP_NAME"
BIN_PATH="$APP_DIR/zig-out/bin/MacScheme"
PLIST_TEMPLATE="$APP_DIR/macos/Info.plist"

HOST_ARCH="$(uname -m)"
case "$HOST_ARCH" in
	arm64|aarch64)
		DEFAULT_TARGET_ARCH="arm64"
		;;
	x86_64|amd64)
		DEFAULT_TARGET_ARCH="intel64"
		;;
	*)
		echo "Unsupported host architecture: $HOST_ARCH" >&2
		exit 1
		;;
esac

case "${1:-$DEFAULT_TARGET_ARCH}" in
	arm64|aarch64)
		TARGET_ARCH="arm64"
		ZIG_TARGET="aarch64-macos.14.0"
		LIB_SUBDIR="arm64"
		BOOT_RESOURCE_DIR="$APP_DIR/resources"
		;;
	intel64|intel|x86_64|amd64)
		TARGET_ARCH="intel64"
		ZIG_TARGET="x86_64-macos.14.0"
		LIB_SUBDIR="intel64"
		BOOT_RESOURCE_DIR="$APP_DIR/resources/intel64"
		;;
	*)
		echo "Usage: $0 [arm64|intel64]" >&2
		echo "Default target on this host: $DEFAULT_TARGET_ARCH" >&2
		exit 1
		;;
esac

LIB_DIR="$APP_DIR/lib/$LIB_SUBDIR"
ZIP_PATH="$DIST_DIR/MacScheme-macos-$TARGET_ARCH.zip"
XCODE_SDK_PATH="/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk"

if [[ -d "$XCODE_SDK_PATH" && -f "$XCODE_SDK_PATH/usr/include/libDER/DERItem.h" ]]; then
	SDKROOT_PATH="$XCODE_SDK_PATH"
else
	SDKROOT_PATH="$(xcrun --show-sdk-path)"
fi

SDK_LIB_DIR="$SDKROOT_PATH/usr/lib"
SDK_FRAMEWORK_DIR="$SDKROOT_PATH/System/Library/Frameworks"
SDK_INCLUDE_DIR="$SDKROOT_PATH/usr/include"

if [[ ! -f "$LIB_DIR/libkernel.a" || ! -f "$LIB_DIR/libz.a" || ! -f "$LIB_DIR/liblz4.a" ]]; then
	echo "Missing Chez static libraries in $LIB_DIR" >&2
	exit 1
fi

if [[ ! -f "$BOOT_RESOURCE_DIR/petite.boot" || ! -f "$BOOT_RESOURCE_DIR/scheme.boot" ]]; then
	echo "Missing Chez boot files in $BOOT_RESOURCE_DIR" >&2
	exit 1
fi

if [[ ! -d "$SDK_LIB_DIR" ]]; then
	echo "Missing macOS SDK library directory at $SDK_LIB_DIR" >&2
	exit 1
fi

if [[ ! -d "$SDK_FRAMEWORK_DIR" ]]; then
	echo "Missing macOS SDK framework directory at $SDK_FRAMEWORK_DIR" >&2
	exit 1
fi

if [[ ! -d "$SDK_INCLUDE_DIR" ]]; then
	echo "Missing macOS SDK include directory at $SDK_INCLUDE_DIR" >&2
	exit 1
fi

cd "$APP_DIR"
zig build -Dtarget="$ZIG_TARGET" -Dchez-lib-dir="lib/$LIB_SUBDIR" -Dmacos-sdk-lib-dir="$SDK_LIB_DIR" -Dmacos-sdk-framework-dir="$SDK_FRAMEWORK_DIR" -Dmacos-sdk-include-dir="$SDK_INCLUDE_DIR"

mkdir -p "$DIST_DIR"
rm -rf "$DEST_APP" "$ZIP_PATH"

mkdir -p "$DEST_APP/Contents/MacOS" "$DEST_APP/Contents/Resources"
cp "$BIN_PATH" "$DEST_APP/Contents/MacOS/MacScheme"
chmod +x "$DEST_APP/Contents/MacOS/MacScheme"
cp "$PLIST_TEMPLATE" "$DEST_APP/Contents/Info.plist"

cp "$BOOT_RESOURCE_DIR/petite.boot" "$DEST_APP/Contents/Resources/petite.boot"
cp "$BOOT_RESOURCE_DIR/scheme.boot" "$DEST_APP/Contents/Resources/scheme.boot"
cp "$APP_DIR/resources/MacScheme.icns" "$DEST_APP/Contents/Resources/MacScheme.icns"
if [[ -d "$ROOT_DIR/docs" ]]; then
	ditto "$ROOT_DIR/docs" "$DEST_APP/Contents/Resources/docs"
fi
/usr/libexec/PlistBuddy -c "Delete :CFBundleIconFile" "$DEST_APP/Contents/Info.plist" >/dev/null 2>&1 || true
/usr/libexec/PlistBuddy -c "Add :CFBundleIconFile string MacScheme.icns" "$DEST_APP/Contents/Info.plist"
codesign --force --deep --sign - "$DEST_APP"

ditto -c -k --sequesterRsrc --keepParent "$DEST_APP" "$ZIP_PATH"

echo "Created app bundle: $DEST_APP"
echo "Created zip archive: $ZIP_PATH"