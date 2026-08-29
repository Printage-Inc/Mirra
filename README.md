# Mirra

Mirra is a native macOS app that shows the live display of an iPhone or iPad over a USB data cable. It uses Apple's public AVFoundation and CoreMediaIO APIs and keeps all video local to the Mac.

## What works in this MVP

- Detect Apple screen-capture sources over USB; webcams, Continuity Camera, and virtual cameras such as OBS are excluded.
- Reject wireless and Continuity Camera sources so the app never shows the iPhone camera by mistake.
- Enumerate both modern external capture extensions and the legacy `ExternalUnknown` type still used by Apple's QuickTime-compatible `iOSScreenCapture` plug-in.
- Automatically start a low-latency aspect-fit preview in presentation mode.
- Start with a portrait-oriented window and keep the complete screen aspect-fit with minimal letterboxing; the window remains safely resizable by the user.
- Register a lightweight macOS LaunchAgent that opens Mirra when a USB iPhone or iPad is connected.
- Preserve the phone's own touch interaction while mirroring.
- Handle portrait, landscape, and live orientation changes without a model table.
- Switch between multiple connected devices.
- Keep the mirror window above other apps.
- Enter a clean presentation mode with **Shift-Command-P**, then share the window named **Mirra** in Zoom, Google Meet, Teams, or another conferencing app.
- Copy a privacy-safe JSON diagnostics report for physical-device certification.
- Build a universal Intel + Apple silicon `.app` and `.dmg`.

## Important platform boundary

Mirra does not send Mac mouse or keyboard events to a physical iPhone. Apple does not provide a public third-party API for arbitrary wired iPhone input. Apple's own iPhone Mirroring feature can control a phone, but it is a separate system feature with different requirements and it locks the physical iPhone during use.

## Build and test

Full Xcode is required. The scripts explicitly use the standard Xcode install even if `xcode-select` currently points at Command Line Tools.

```sh
cd /Users/vivi/code/NuStack/Mirra
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --disable-sandbox
./scripts/build-app.sh
```

Every packaging run creates a timestamped artifact instead of overwriting an earlier build. The script prints the resulting `.app` and `.dmg` paths.

The default build is ad-hoc signed for local testing. For direct distribution, set a Developer ID identity:

```sh
CODESIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)" ./scripts/build-app.sh
./scripts/notarize.sh /absolute/path/to/Mirra.dmg your-notary-keychain-profile
```

The default package is the direct-distribution build. It uses Hardened Runtime plus the Camera hardware entitlement, matching the permission model used by Bezel's direct download. It intentionally does not enable App Sandbox because the macOS iOS-screen-capture plug-in does not publish the wired display source to this app in the sandboxed test build.

`Resources/CableMirror-AppStore.entitlements` is kept as an experimental App Store profile. It is not used for the standalone DMG until wired capture is verified under App Sandbox on every supported macOS release.

To create that experimental package explicitly, set `ENTITLEMENTS_FILE` when invoking the build script:

```sh
ENTITLEMENTS_FILE="$PWD/Resources/CableMirror-AppStore.entitlements" ./scripts/build-app.sh
```

## First-run test

1. Connect an unlocked iPhone with a data-capable cable.
2. Approve **Trust This Computer** on the iPhone if prompted.
3. Drag Mirra into **Applications**, then open that installed copy once. This registers the bundled USB device watcher; opening the copy directly from the DMG cannot enable persistent automatic launch.
4. Grant Camera access. macOS exposes the wired display as a video capture source, so this permission name is expected.
5. If macOS reports that the background item needs approval, enable Mirra under **System Settings → General → Login Items & Extensions**.
6. If no device appears, verify it first appears under QuickTime Player → File → New Movie Recording → Camera.
7. Use **Copy Diagnostics** and add the result to the release test record.

## Connection scope

Mirra 1.0 is intentionally USB-only. It does not request Screen Recording, Local Network, Bluetooth, or Bonjour access. Apple's public APIs do not expose a dependable way for a third-party Mac app to receive the system AirPlay display and embed that protected receiver surface inside its own window without a companion app on the iPhone or iPad.

See [docs/COMPATIBILITY.md](docs/COMPATIBILITY.md) for the physical-device release matrix.
