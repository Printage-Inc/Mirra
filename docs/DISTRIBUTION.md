# Mirra direct-distribution release

Mirra is distributed outside the Mac App Store as a Developer ID signed and Apple-notarized DMG. Do not publish the ad-hoc test package produced when `CODESIGN_IDENTITY` is omitted.

## One-time Apple setup

1. Enrol the release owner in the Apple Developer Program.
2. Create and install a **Developer ID Application** certificate, including its private key, in the login keychain.
3. Confirm that macOS can use the identity:

   ```sh
   security find-identity -v -p codesigning
   ```

4. Create an app-specific password for the release Apple Account, then store it directly in the Keychain. Enter the password at the secure prompt; never save it in this repository:

   ```sh
   xcrun notarytool store-credentials MirraNotary \
     --apple-id RELEASE_APPLE_ID \
     --team-id TEAM_ID
   ```

## Release

```sh
cd /Users/vivi/code/NuStack/Mirra
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
  swift test --disable-sandbox

CODESIGN_IDENTITY="Developer ID Application: RELEASE_OWNER (TEAM_ID)" \
  ./scripts/build-app.sh

./scripts/notarize.sh /absolute/path/to/Mirra-VERSION-TIMESTAMP.dmg MirraNotary
```

The build enables Hardened Runtime, signs the device watcher and app, signs the DMG, and creates the current Apple-silicon release artifact. It also places `LICENSE.txt`, third-party notices, and the complete corresponding GPL source ZIP in the DMG. The notarization script uploads the DMG, waits for Apple, staples the ticket, and validates the final Gatekeeper result.

## Publish only after

- All tests pass.
- `codesign -d --verbose=4 Mirra.app` shows `Developer ID Application` and a Team ID, not `Signature=adhoc`.
- `xcrun stapler validate Mirra.dmg` succeeds.
- `spctl` accepts the DMG.
- A clean Mac can drag Mirra to Applications, grant Camera access, approve the background item if requested, and display a trusted iPhone/iPad over USB.
- The same clean Mac grants Local Network access, advertises `Mirra: <Mac name>`, requires the displayed four-digit code on first use, remembers that verified AirPlay public key for 30 days across app relaunches, and keeps the video inside Mirra.
- The source ZIP in the DMG builds the same release from the pinned UxPlay, bridge, OpenSSL, and libplist revisions.
- Any download page identifies Mirra as GPLv3 and provides the corresponding source alongside the binary.
