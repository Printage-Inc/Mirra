# Mirra compatibility plan

Mirra intentionally does not hard-code iPhone model dimensions or decorative bezels. It renders the dimensions delivered by the capture stream with aspect-fit behavior, so portrait, landscape, older 16:9 devices, and newer tall displays use the same path.

## Supported product contract

- Mac: macOS 13 or later, Intel or Apple silicon.
- Device: an iPhone, iPad, or iPod touch that appears as a wired screen capture source in QuickTime Player.
- Connection: a data-capable Lightning or USB-C cable.
- First connection: the device must be unlocked and the user must approve **Trust This Computer**.
- Phone interaction: the physical phone remains unlocked and usable while its display is mirrored.
- Mac input: clicks and keystrokes are not sent to the phone. Apple does not publish a third-party API for that behavior.

## Physical-device release matrix

Passing a simulator or a dimensions test is not evidence that a real USB device works. Before a public release, record a diagnostic report and complete the following checks on at least one device from each row.

| Hardware family | Connector | Minimum physical coverage | Portrait | Landscape | Rotate while streaming | Lock/unlock | Reconnect |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| iPhone SE / Home button | Lightning | 1 model | ☐ | ☐ | ☐ | ☐ | ☐ |
| iPhone 8–14 | Lightning | 1 standard + 1 Plus/Max | ☐ | ☐ | ☐ | ☐ | ☐ |
| iPhone 15–current | USB-C | 1 standard + 1 Pro/Max/Air | ☐ | ☐ | ☐ | ☐ | ☐ |
| iPad (optional) | Lightning | 1 model | ☐ | ☐ | ☐ | ☐ | ☐ |
| iPad (optional) | USB-C | 1 model | ☐ | ☐ | ☐ | ☐ | ☐ |

For every row, also verify:

1. Mirra appears in macOS Camera privacy settings.
2. The source becomes available within five seconds of trust approval.
3. The preview has no crop, stretch, black-frame flash loop, or upside-down output.
4. Touch, Face ID/Touch ID, keyboard input, audio playback, and app switching still work on the phone.
5. Disconnecting the cable returns to the waiting screen without crashing.
6. Reconnecting selects the same device automatically.
7. Copy Diagnostics produces the expected formats without a hardware serial number.
8. With Mirra closed, connecting the device starts the installed app through the approved background item.
9. Presentation mode keeps the complete screen visible and automatically follows portrait/landscape aspect changes with no material letterboxing.

## Why this is model-independent, not “all models certified”

The capture pipeline is model-independent. Certification still requires real hardware because cable quality, trust state, macOS/iOS combinations, and Apple capture-service regressions cannot be proven by source code. Do not claim “all iPhones verified” until the release matrix contains actual device and OS results.
