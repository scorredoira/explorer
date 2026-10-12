#!/bin/zsh
set -e
cd "$(dirname "$0")"
swift build -c release
APP=build/Explorer.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Explorer "$APP/Contents/MacOS/Explorer"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.scorredoira.explorer</string>
  <key>CFBundleName</key><string>Explorer</string>
  <key>CFBundleDisplayName</key><string>Explorer</string>
  <key>CFBundleExecutable</key><string>Explorer</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>NSHighResolutionCapable</key><true/>
  <key>NSPrincipalClass</key><string>NSApplication</string>
  <key>CFBundleDevelopmentRegion</key><string>es</string>
  <key>CFBundleDocumentTypes</key>
  <array>
    <dict>
      <key>CFBundleTypeRole</key><string>Viewer</string>
      <key>LSHandlerRank</key><string>None</string>
      <key>LSItemContentTypes</key><array><string>public.folder</string><string>public.item</string></array>
    </dict>
  </array>
</dict>
</plist>
PLIST
IDENTITY="${EXPLORER_SIGN_IDENTITY:-Apple Development: Santiago Corredoira (B378K896LB)}"
codesign --force --sign "$IDENTITY" "$APP" 2>/dev/null || codesign --force --sign - "$APP"
echo "$APP"
