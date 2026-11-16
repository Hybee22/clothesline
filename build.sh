#!/bin/bash
# Builds Clothesline.app and installs it in /Applications.
#   ./build.sh               build, install and start
#   ./build.sh --no-install  only build into build/Clothesline.app
set -euo pipefail
cd "$(dirname "$0")"

APP="build/Clothesline.app"
swift build -c release
rm -rf build && mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$(swift build -c release --show-bin-path)/Clothesline" "$APP/Contents/MacOS/Clothesline"

# App icon (cached in .build so it's only drawn once)
ICNS=".build/AppIcon.icns"
if [[ ! -f "$ICNS" || scripts/make-icon.swift -nt "$ICNS" ]]; then
  SET=".build/AppIcon.iconset"
  rm -rf "$SET" && mkdir -p "$SET"
  swift scripts/make-icon.swift .build/icon-1024.png
  for s in 16 32 128 256 512; do
    sips -z $s $s .build/icon-1024.png --out "$SET/icon_${s}x${s}.png" >/dev/null
    sips -z $((s*2)) $((s*2)) .build/icon-1024.png --out "$SET/icon_${s}x${s}@2x.png" >/dev/null
  done
  iconutil -c icns "$SET" -o "$ICNS"
fi
cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
  <key>CFBundleIdentifier</key><string>dev.ibrahim.clothesline</string>
  <key>CFBundleName</key><string>Clothesline</string>
  <key>CFBundleDisplayName</key><string>Clothesline</string>
  <key>CFBundleExecutable</key><string>Clothesline</string>
  <key>CFBundleIconFile</key><string>AppIcon</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>1.0</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSHumanReadableCopyright</key><string>Your clipboard, hung out to dry.</string>
  <key>CFBundleURLTypes</key><array><dict>
    <key>CFBundleURLName</key><string>Clothesline commands</string>
    <key>CFBundleURLSchemes</key><array><string>clothesline</string></array>
  </dict></array>
</dict></plist>
PLIST
codesign --force -s - "$APP"

if [[ "${1:-}" != "--no-install" ]]; then
  osascript -e 'tell application id "dev.ibrahim.clothesline" to quit' 2>/dev/null || true
  sleep 1; pkill -x Clothesline || true
  rm -rf /Applications/Clothesline.app
  cp -R "$APP" /Applications/
  LSREG=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
  # Remove the build copy so Spotlight and Launchpad show only the installed app.
  $LSREG -u "$APP" 2>/dev/null || true
  rm -rf build
  $LSREG -f /Applications/Clothesline.app
  open /Applications/Clothesline.app
  echo "Installed and started /Applications/Clothesline.app"
fi
