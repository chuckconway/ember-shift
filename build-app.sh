#!/bin/zsh
# Builds Ember Shift.app (release), ad-hoc signs it, and installs it to ~/Applications.
set -euo pipefail
cd "${0:A:h}"

swift run -c release EmberChecks
swift build -c release --product Ember

app="build/Ember Shift.app"
rm -rf "$app"
mkdir -p "$app/Contents/MacOS"
cp .build/release/Ember "$app/Contents/MacOS/Ember"
cat > "$app/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleIdentifier</key><string>com.cconway.ember</string>
  <key>CFBundleName</key><string>Ember Shift</string>
  <key>CFBundleDisplayName</key><string>Ember Shift</string>
  <key>CFBundleExecutable</key><string>Ember</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.5.1</string>
  <key>CFBundleVersion</key><string>1</string>
  <key>LSMinimumSystemVersion</key><string>14.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationUsageDescription</key><string>Ember Shift uses your approximate location to compute sunrise and sunset.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Ember Shift uses your approximate location to compute sunrise and sunset.</string>
</dict>
</plist>
PLIST
codesign --force --sign - "$app"

pkill -x Ember 2>/dev/null && sleep 1 || true
# Ember.app is the pre-rename bundle.
rm -rf ~/Applications/Ember.app ~/Applications/"Ember Shift.app"
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Ember Shift.app"
