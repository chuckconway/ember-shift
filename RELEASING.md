# Releasing

Source builds (`./build-app.sh`) are ad hoc signed and only run on the Mac that built them. A downloadable build has to be signed with a Developer ID and notarized by Apple, or Gatekeeper blocks it.

Every build already uses hardened runtime and `Ember.entitlements`, which notarization requires, so a release build differs from a source build only in its signing identity.

## One-time setup

1. Join the [Apple Developer Program](https://developer.apple.com/programs/).
2. Create a **Developer ID Application** certificate (Xcode → Settings → Accounts → Manage Certificates, or the developer portal) and install it in your login keychain. Confirm it's there:
   ```sh
   security find-identity -v -p codesigning
   # "Developer ID Application: Your Name (TEAMID)"
   ```
3. Create an app-specific password at [account.apple.com](https://account.apple.com) and store notary credentials in the keychain:
   ```sh
   xcrun notarytool store-credentials ember-notary \
     --apple-id you@example.com --team-id TEAMID --password <app-specific-password>
   ```

`notarytool` and `stapler` ship with Xcode, not the Command Line Tools alone.

## Each release

1. Bump `VERSION`.
2. Build, sign, notarize and staple:
   ```sh
   SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" \
   NOTARY_PROFILE=ember-notary \
   BUILD_NUMBER=2 \
   ./release.sh
   ```
   This produces `build/Ember-Shift-<version>.zip`, checks it with `spctl`, and prints its SHA-256.
3. Tag the commit (`git tag v<version>`), push the tag, and attach the zip to a GitHub release along with its SHA-256.

`BUILD_NUMBER` must increase with every release; macOS uses it to tell builds apart.

## If notarization fails

```sh
xcrun notarytool log <submission-id> --keychain-profile ember-notary
```

The log names the binary and the rule it broke, usually a missing hardened runtime flag or an unsigned nested binary.
