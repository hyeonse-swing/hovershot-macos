#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-release}"
DIST_DIR="$ROOT_DIR/dist"
APP_NAME="HoverShot"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
ZIP_PATH="$DIST_DIR/$APP_NAME-macOS.zip"
CHECKSUM_PATH="$DIST_DIR/$APP_NAME-macOS.sha256"
USER_GUIDE_PATH="$DIST_DIR/$APP_NAME User Guide.md"
USER_GUIDE_KO_PATH="$DIST_DIR/$APP_NAME User Guide (KO).md"
PACKAGE_DIR="$DIST_DIR/$APP_NAME Package"

cd "$ROOT_DIR"

"$ROOT_DIR/scripts/build-app-bundle.sh" "$CONFIGURATION" >/dev/null

rm -f "$ZIP_PATH" "$CHECKSUM_PATH" "$USER_GUIDE_PATH" "$USER_GUIDE_KO_PATH"
rm -rf "$PACKAGE_DIR"

cp "$ROOT_DIR/docs/user-guide.md" "$USER_GUIDE_PATH"
cp "$ROOT_DIR/docs/user-guide.ko.md" "$USER_GUIDE_KO_PATH"

mkdir -p "$PACKAGE_DIR"
cp -R "$APP_BUNDLE" "$PACKAGE_DIR/"
cp "$USER_GUIDE_PATH" "$PACKAGE_DIR/"
cp "$USER_GUIDE_KO_PATH" "$PACKAGE_DIR/"

ditto -c -k --sequesterRsrc --keepParent "$PACKAGE_DIR" "$ZIP_PATH"
(cd "$DIST_DIR" && shasum -a 256 "$APP_NAME-macOS.zip") > "$CHECKSUM_PATH"

echo "Packaged build:"
echo "$ZIP_PATH"
echo
echo "SHA-256:"
cat "$CHECKSUM_PATH"
