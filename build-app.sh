#!/bin/zsh
# Builds Ember Shift.app (release) with hardened runtime, signs it, and installs it to ~/Applications.
#
#   SIGN_IDENTITY  codesign identity; default "-" (ad hoc). release.sh passes a Developer ID.
#   INSTALL=0      build and sign only; leave ~/Applications alone.
set -euo pipefail
cd "${0:A:h}"

identity="${SIGN_IDENTITY:--}"
version="$(<VERSION)"
build_number="${BUILD_NUMBER:-1}"

swift run -c release EmberChecks
swift run EmberKitChecks  # debug: it uses @testable import
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
  <key>CFBundleShortVersionString</key><string>$version</string>
  <key>CFBundleVersion</key><string>$build_number</string>
  <key>LSMinimumSystemVersion</key><string>15.0</string>
  <key>LSUIElement</key><true/>
  <key>NSLocationUsageDescription</key><string>Ember Shift uses your approximate location to compute sunrise and sunset.</string>
  <key>NSLocationWhenInUseUsageDescription</key><string>Ember Shift uses your approximate location to compute sunrise and sunset.</string>
</dict>
</plist>
PLIST

# Hardened runtime is what notarization requires; using it for ad hoc builds too surfaces entitlement problems early.
sign_flags=(--force --options runtime --entitlements Ember.entitlements --sign "$identity")
[[ "$identity" != "-" ]] && sign_flags+=(--timestamp)
codesign "${sign_flags[@]}" "$app"
codesign --verify --strict "$app"
echo "Signed $app ($identity)"

[[ "${INSTALL:-1}" == 0 ]] && exit 0
pkill -x Ember 2>/dev/null && sleep 1 || true
# Ember.app is the pre-rename bundle.
rm -rf ~/Applications/Ember.app ~/Applications/"Ember Shift.app"
cp -R "$app" ~/Applications/
echo "Installed ~/Applications/Ember Shift.app"
