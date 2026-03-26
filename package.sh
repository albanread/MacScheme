#!/bin/zsh
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$ROOT_DIR/MacScheme"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="MacScheme.app"
SOURCE_APP="$APP_DIR/zig-out/$APP_NAME"
DEST_APP="$DIST_DIR/$APP_NAME"
ZIP_PATH="$DIST_DIR/MacScheme-macos.zip"

cd "$APP_DIR"
zig build

mkdir -p "$DIST_DIR"
rm -rf "$DEST_APP" "$ZIP_PATH"
ditto "$SOURCE_APP" "$DEST_APP"

mkdir -p "$DEST_APP/Contents/Resources"
cp "$APP_DIR/resources/petite.boot" "$DEST_APP/Contents/Resources/petite.boot"
cp "$APP_DIR/resources/scheme.boot" "$DEST_APP/Contents/Resources/scheme.boot"

ditto -c -k --sequesterRsrc --keepParent "$DEST_APP" "$ZIP_PATH"

echo "Created app bundle: $DEST_APP"
echo "Created zip archive: $ZIP_PATH"