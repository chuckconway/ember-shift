#!/bin/zsh
# Builds a Developer ID signed, notarized, stapled zip of Ember Shift for download.
# One-time setup is in RELEASING.md.
#
#   SIGN_IDENTITY   e.g. "Developer ID Application: Your Name (TEAMID)"
#   NOTARY_PROFILE  keychain profile created with `xcrun notarytool store-credentials`
set -euo pipefail
cd "${0:A:h}"

: "${SIGN_IDENTITY:?Set SIGN_IDENTITY to your Developer ID Application identity (see RELEASING.md)}"
: "${NOTARY_PROFILE:?Set NOTARY_PROFILE to your notarytool keychain profile (see RELEASING.md)}"
[[ "$SIGN_IDENTITY" == "-" ]] && { echo "release.sh needs a Developer ID, not ad hoc signing" >&2; exit 1; }

version="$(<VERSION)"
app="build/Ember Shift.app"
zip="build/Ember-Shift-$version.zip"

SIGN_IDENTITY="$SIGN_IDENTITY" INSTALL=0 ./build-app.sh

rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
xcrun notarytool submit "$zip" --keychain-profile "$NOTARY_PROFILE" --wait
xcrun stapler staple "$app"

# Re-zip so the download carries the stapled ticket and opens offline.
rm -f "$zip"
ditto -c -k --keepParent "$app" "$zip"
spctl --assess --type execute --verbose "$app"
shasum -a 256 "$zip"
echo "Release ready: $zip"
