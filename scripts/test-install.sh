#!/bin/bash
# Checks install-app.sh against throwaway folders. It never touches /Applications.
set -euo pipefail
cd "$(dirname "$0")/.."
INSTALL="$PWD/scripts/install-app.sh"
# These checks use throwaway folders; they must not touch the real app registry.
export EMBER_SKIP_LSREGISTER=1
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

fail() { echo "FAIL: $1" >&2; exit 1; }

# A minimal bundle with an identifier and a marker file to tell copies apart.
make_app() {
    mkdir -p "$1/Contents"
    printf '<?xml version="1.0" encoding="UTF-8"?>\n<plist version="1.0"><dict><key>CFBundleIdentifier</key><string>%s</string></dict></plist>\n' "$2" > "$1/Contents/Info.plist"
    echo "$3" > "$1/Contents/marker"
}
marker() { cat "$1/Contents/marker" 2>/dev/null || echo missing; }

BUILT="$WORK/build/Ember Shift.app"
make_app "$BUILT" com.cconway.ember new-build

# 1. Another app sits at the install path: refuse, change nothing.
D="$WORK/foreign"; F="$WORK/foreign-former"
make_app "$D/Ember Shift.app" com.apple.Safari.WebApp.SOMEONE-ELSE web-app
make_app "$F/Ember Shift.app" com.cconway.ember former-build
if EMBER_INSTALL_DIR="$D" EMBER_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null 2>&1; then
    fail "installed over a different app"
fi
[ "$(marker "$D/Ember Shift.app")" = web-app ] || fail "the other app was changed"
[ "$(marker "$F/Ember Shift.app")" = former-build ] || fail "a refused install still removed the former copy"

# 2. Our old build is at the install path: replace it.
D="$WORK/upgrade"
make_app "$D/Ember Shift.app" com.cconway.ember old-build
EMBER_INSTALL_DIR="$D" EMBER_FORMER_DIR="$WORK/none" "$INSTALL" "$BUILT" >/dev/null
[ "$(marker "$D/Ember Shift.app")" = new-build ] || fail "our old build was not replaced"

# 3. An earlier install in the former location is ours: it goes. A lookalike-named app there stays.
D="$WORK/move"; F="$WORK/former"
make_app "$F/Ember Shift.app" com.cconway.ember former-build
EMBER_INSTALL_DIR="$D" EMBER_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null
[ ! -e "$F/Ember Shift.app" ] || fail "our copy in the former location was left behind"
[ "$(marker "$D/Ember Shift.app")" = new-build ] || fail "the move did not install"
make_app "$F/Ember Shift.app" com.apple.Safari.WebApp.LOOKALIKE someone-else
EMBER_INSTALL_DIR="$D" EMBER_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null
[ "$(marker "$F/Ember Shift.app")" = someone-else ] || fail "an unrelated app in the former location was removed"

# 4. The thing being installed is not an Ember Shift build: refuse.
make_app "$WORK/build/Other.app" com.example.other other
if EMBER_INSTALL_DIR="$WORK/empty" EMBER_FORMER_DIR="$WORK/none" "$INSTALL" "$WORK/build/Other.app" >/dev/null 2>&1; then
    fail "installed a bundle that is not ours"
fi

# 5. The pre-rename Ember.app goes when it is ours, and stays when it is not.
D="$WORK/rename"; F="$WORK/rename-former"
make_app "$F/Ember.app" com.cconway.ember pre-rename
make_app "$D/Ember.app" com.apple.Safari.WebApp.EMBER someone-else
EMBER_INSTALL_DIR="$D" EMBER_FORMER_DIR="$F" "$INSTALL" "$BUILT" >/dev/null
[ ! -e "$F/Ember.app" ] || fail "our pre-rename Ember.app was left behind"
[ "$(marker "$D/Ember.app")" = someone-else ] || fail "an unrelated Ember.app was removed"

echo "install-app.sh: 5 checks passed"
