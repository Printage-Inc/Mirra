# Mirra third-party notices

Mirra's wireless receiver is distributed under GNU GPL version 3 because it
links GPL-covered AirPlay receiver code. The exact source revisions used by
this release are pinned as Git submodules and are included in the source
archive shipped beside `Mirra.app` in the DMG.

| Component | Revision | License | Purpose |
| --- | --- | --- | --- |
| [UxPlay](https://github.com/FDH2/UxPlay) | `1dfca6de687af97d1daf087db083365a50f14141` | GPL-3.0 | AirPlay/RAOP receiver protocol |
| [airlive-bridge](https://github.com/airlive-project/airlive-bridge) | `ab93d012920305f89bbe262cc7b14f26b1a9263c` | GPL-3.0 | Objective-C++ and VideoToolbox bridge |
| [OpenSSL](https://github.com/openssl/openssl) | `f4dc4d58b48d346a8270183f89acf826d459b0ca` (3.5.8) | Apache-2.0 | Receiver cryptography |
| [libplist](https://github.com/libimobiledevice/libplist) | `cf5897a71ea412ea2aeb1e2f6b5ea74d4fabfd8c` (2.7.0) | LGPL-2.1-or-later | Apple property-list parsing |

The complete license texts and copyright notices remain in each component's
source directory. Mirra's own source is available under GPL-3.0 in `LICENSE`.
No Homebrew library is embedded or required at runtime: release builds compile
the pinned OpenSSL and libplist sources as static libraries for the declared
macOS deployment target.
