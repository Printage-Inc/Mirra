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
cd /Users/vivi/code/NuStack/CableMirror
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
  CLANG_MODULE_CACHE_PATH="$PWD/.build/ModuleCache" \
  swift test --disable-sandbox

CODESIGN_IDENTITY="Developer ID Application: RELEASE_OWNER (TEAM_ID)" \
  ./scripts/build-app.sh

./scripts/notarize.sh /absolute/path/to/Mirra-VERSION-TIMESTAMP.dmg MirraNotary
```

The build enables Hardened Runtime, signs the device watcher and app, signs the DMG, and creates a universal Intel/Apple-silicon binary. The notarization script uploads the DMG, waits for Apple, staples the ticket, and validates the final Gatekeeper result.

## Publish only after

- All tests pass.
- `codesign -d --verbose=4 Mirra.app` shows `Developer ID Application` and a Team ID, not `Signature=adhoc`.
- `xcrun stapler validate Mirra.dmg` succeeds.
- `spctl` accepts the DMG.
- A clean Mac can drag Mirra to Applications, grant Camera access, approve the background item if requested, and display a trusted iPhone/iPad over USB.
