#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/MacScheme"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacScheme.app"
DEST_APP="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/MacScheme-macos.zip"
BIN_PATH="$APP_DIR/zig-out/bin/MacScheme"
PLIST_TEMPLATE="$APP_DIR/macos/Info.plist"

cd "$APP_DIR"
zig build

mkdir -p "$DIST_DIR"
rm -rf "$DEST_APP" "$ZIP_PATH"

mkdir -p "$DEST_APP/Contents/MacOS" "$DEST_APP/Contents/Resources"
cp "$BIN_PATH" "$DEST_APP/Contents/MacOS/MacScheme"
chmod +x "$DEST_APP/Contents/MacOS/MacScheme"
cp "$PLIST_TEMPLATE" "$DEST_APP/Contents/Info.plist"

cp "$APP_DIR/resources/petite.boot" "$DEST_APP/Contents/Resources/petite.boot"
cp "$APP_DIR/resources/scheme.boot" "$DEST_APP/Contents/Resources/scheme.boot"
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