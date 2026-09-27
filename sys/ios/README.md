# NetHack iOS — Gurr 3.6.6 interface on NetHack 5.0.0

Target: iPhone 14 Pro; personal installation with SideStore. The user verified installation of the initial probe on their reported iOS 26.6.2 device.

## Build and install

The **iOS game build** workflow compiles the game on macOS and creates `NetHack-ios-unsigned.ipa`. Download its artifact ZIP, extract the IPA in Files on the iPhone, and import it into SideStore. Keep the existing app installed when updating to retain its sandbox. Signing happens in SideStore; no Apple credentials are needed in this repository.

On a Mac with Xcode: `bash sys/ios/build.sh game`. Run `python3 sys/ios/simulate.py` afterward to launch the UIKit app in an available iPhone simulator and capture its game screen. The original Swift installation probe remains available through `bash sys/ios/build.sh` and the separate manual workflow.

## Gurr interface revision (0.4.0)

See [GURR-UI.md](GURR-UI.md) for pinned source references, implemented controls, attribution and remaining differences. This revision replaces the provisional fixed button grid with the Gurr command panels and keyboard. The NetHack 5.0.0 engine is retained.

## Implemented

- Real NetHack 5.0.0 C engine, Lua 5.4.8, generated game data, and original default tiles.
- Reuse of the Android C window port through an in-process compatibility adapter. There is no Java VM in the app.
- Background engine thread; UIKit map, messages, status, menus, name/text prompts, and input queue.
- Gurr-style overlays for text prompts, yes/no questions, inventory menus, pickup and multi-item selection, item quantities, and long text windows.
- Eight-direction buttons, basic command buttons, keyboard input, free map dragging, focus-preserving pinch zoom, map targeting, directional tap and long-press travel.
- The Gurr Android NetHack app icon, compiled into the iOS app bundle.
- Save-and-exit command; restoring by entering the same character name after relaunch.
- Writable data under Documents/NetHack, visible through Files. Backgrounding requests a save on the engine thread within an iOS background task. iOS can interrupt this; use Save explicitly before ending a session.

## Verification

CI runs the actual engine and adapter as a native macOS executable in a temporary playground: start a game, render glyphs, process four turns, save, start a fresh process, restore, process four more turns, and save again. It requires a nonempty save file and a restoration message. This passed in game build #3.

The additional simulator check launches the actual UIKit binary using a dedicated test character, captures the map and modal screens, checks prompt and question responses, exercises grouped item-menu selection, verifies map pan/pinch math, and confirms the icon asset is bundled. It does not replace physical-device touch testing or extended play.

## Remaining differences

The UIKit implementation is not pixel-identical to Android. See GURR-UI.md for the remaining differences and device checks. Save ends the engine session; close and reopen to resume with the same name.

## Source baseline

- NetHack-Android: f7c0d7851b854cc7b1ca09b2c193e8620f2962d9.
- ForkFront touch behavior reference: tag 2.8, commit 1ce8a040c932992fa125d2775160f2556d5601e6.
- Lua version matches the Android build's 5.4.8 setting. Host generators and device libraries are built separately.
- Upstream license and notices are retained; the game data bundle includes `license`.
