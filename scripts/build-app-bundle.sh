#!/bin/zsh

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
CONFIGURATION="${1:-debug}"
APP_NAME="HoverShot"
EXECUTABLE_NAME="HoverShotMac"
BUNDLE_ID="app.hovershot.mac"
VERSION="0.1.0"
cd "$ROOT_DIR"
swift build -c "$CONFIGURATION" >/dev/null
BUILD_DIR="$(swift build -c "$CONFIGURATION" --show-bin-path)"
EXECUTABLE_PATH="$BUILD_DIR/$EXECUTABLE_NAME"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"
INFO_PLIST="$CONTENTS_DIR/Info.plist"
PREFERRED_SIGN_IDENTITY="HoverShot Local Development"
SIGN_IDENTITY="${HOVERSHOT_CODESIGN_IDENTITY:-${CODE_SIGN_IDENTITY:-}}"

if [[ ! -x "$EXECUTABLE_PATH" ]]; then
  echo "Expected executable not found at $EXECUTABLE_PATH" >&2
  exit 1
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  if security find-identity -v -p codesigning 2>/dev/null | grep -F "\"$PREFERRED_SIGN_IDENTITY\"" >/dev/null; then
    SIGN_IDENTITY="$PREFERRED_SIGN_IDENTITY"
  fi
fi

if [[ -z "$SIGN_IDENTITY" ]]; then
  AVAILABLE_IDENTITIES="$(
    security find-identity -v -p codesigning 2>/dev/null \
      | sed -n 's/.*"\(.*\)"/\1/p'
  )"
  SIGN_IDENTITY="$(printf '%s\n' "$AVAILABLE_IDENTITIES" | head -n 1 | tr -d '\r')"
fi

mkdir -p "$APP_BUNDLE"
rm -rf "$CONTENTS_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$EXECUTABLE_PATH" "$MACOS_DIR/$EXECUTABLE_NAME"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

cat > "$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "https://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleDisplayName</key>
  <string>${APP_NAME}</string>
  <key>CFBundleExecutable</key>
  <string>${EXECUTABLE_NAME}</string>
  <key>CFBundleIdentifier</key>
  <string>${BUNDLE_ID}</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>${APP_NAME}</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>CFBundleShortVersionString</key>
  <string>${VERSION}</string>
  <key>CFBundleVersion</key>
  <string>1</string>
  <key>LSMinimumSystemVersion</key>
  <string>14.0</string>
  <key>LSUIElement</key>
  <true/>
  <key>NSHighResolutionCapable</key>
  <true/>
  <key>NSMicrophoneUsageDescription</key>
  <string>HoverShot records microphone audio when microphone capture is enabled during screen recording.</string>
  <key>NSScreenCaptureUsageDescription</key>
  <string>HoverShot captures screenshots and screen recordings so you can keep floating reference shots on screen.</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

if [[ -n "$SIGN_IDENTITY" ]]; then
  codesign --force --deep --sign "$SIGN_IDENTITY" "$APP_BUNDLE"
  echo "Signed app bundle with identity:"
  echo "$SIGN_IDENTITY"
else
  codesign --force --deep --sign - "$APP_BUNDLE"
  echo "Warning: no valid codesigning identity was found."
  echo "The app was signed ad hoc, so macOS privacy permissions such as Screen Recording may reset after each rebuild."
  echo "Set HOVERSHOT_CODESIGN_IDENTITY or CODE_SIGN_IDENTITY to a stable signing identity to keep permissions across builds."
fi

echo "Built app bundle:"
echo "$APP_BUNDLE"
