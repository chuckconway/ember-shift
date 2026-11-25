#!/bin/bash
# Installs a built "Ember Shift.app" into /Applications (or $EMBER_INSTALL_DIR).
# build-app.sh calls this; scripts/test-install.sh checks it in throwaway folders.
#
# /Applications, not ~/Applications: menu-bar managers such as Dimble match an icon to its app
# through LaunchServices, and an app in ~/Applications was hidden with no way to reveal it
# (2026-11-23). For the same reason the install leaves exactly one registered copy.
#
# It removes only a bundle it can prove is ours, by CFBundleIdentifier. A file name proves
# nothing: Safari saves web apps into ~/Applications under ordinary names.
set -euo pipefail

APP="${1:?usage: install-app.sh <path to the built .app>}"
DEST_DIR="${EMBER_INSTALL_DIR:-/Applications}"
# Where earlier versions installed. A copy there is removed only if it is ours.
FORMER_DIR="${EMBER_FORMER_DIR:-$HOME/Applications}"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Versions/A/Frameworks/LaunchServices.framework/Versions/A/Support/lsregister
OURS=com.cconway.ember

bundle_id() { /usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$1/Contents/Info.plist" 2>/dev/null || true; }

if [ "$(bundle_id "$APP")" != "$OURS" ]; then
    echo "Refusing: $APP is not an Ember Shift build." >&2
    exit 1
fi

TARGET="$DEST_DIR/$(basename "$APP")"

# Decide everything before removing anything, so a refusal changes nothing.
if [ -e "$TARGET" ] && [ "$(bundle_id "$TARGET")" != "$OURS" ]; then
    echo "Refusing: $TARGET is another app ($(bundle_id "$TARGET")). Nothing changed." >&2
    exit 1
fi

# Earlier installs: the former location, and Ember.app (the bundle's name before the rename) in either.
for old in "$FORMER_DIR/$(basename "$APP")" "$FORMER_DIR/Ember.app" "$DEST_DIR/Ember.app"; do
    [ "$old" != "$TARGET" ] && [ -e "$old" ] || continue
    if [ "$(bundle_id "$old")" = "$OURS" ]; then
        rm -rf "$old"
        echo "Removed $old (an earlier install)."
    else
        echo "Left $old alone: it is not an Ember Shift build."
    fi
done
mkdir -p "$DEST_DIR"
rm -rf "$TARGET"
cp -R "$APP" "$TARGET"
echo "Installed to $TARGET"

# One registered copy: forget every other path macOS holds for this identity (build folders,
# the former location), then register the installed one.
if [ -z "${EMBER_SKIP_LSREGISTER:-}" ] && [ -x "$LSREGISTER" ]; then
    "$LSREGISTER" -dump 2>/dev/null \
        | awk -v id="$OURS" '/^-{20,}/{if (blk ~ ("identifier: +" id "\n")) print blk; blk=""; next} {blk = blk "\n" $0}' \
        | sed -n -E 's/^path: +(.*) \(0x[0-9a-f]+\)$/\1/p' \
        | while IFS= read -r registered; do
            [ "$registered" = "$TARGET" ] || "$LSREGISTER" -u "$registered" 2>/dev/null || true
        done
    "$LSREGISTER" -f "$TARGET"
    echo "Registered $TARGET as the only copy."
fi
