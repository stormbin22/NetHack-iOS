# iPhone port — work in progress

Target: iPhone 14 Pro, user-reported iOS 26.6.2; personal installation using existing SideStore.

## Current deliverable

The Swift application is an **installation probe only**. It does not link or run NetHack and does not reproduce the Android UI yet. No iOS compilation or device installation has been verified locally (the development host is Windows).

Run the `iOS installation probe` workflow manually in the user's GitHub repository. Download the artifact ZIP, extract `NetHack-install-probe-unsigned.ipa`, transfer it to Files on the iPhone, and import it into SideStore. Signing takes place in SideStore; do not upload Apple passwords, certificates, or pairing files to GitHub. A successful launch displays an installation confirmation.

macOS local equivalent: `bash sys/ios/build.sh` with Xcode installed. The output targets arm64 iPhone devices, not the simulator.

## Source baseline

- NetHack-Android: f7c0d78 (5.0.0, post-release source).
- ForkFront-Android: tag 2.8, commit 1ce8a040c932992fa125d2775160f2556d5601e6.
- Upstream game and frontend notices must be retained when incorporating their source/assets.

## Remaining implementation

1. Build host tools and game data, initialize the pinned Lua submodule, and cross-compile the C engine for iOS.
2. Replace Android JNI callbacks in `sys/android/winandroid.c` with an iOS window port and a blocking input queue; keep engine execution off the UI thread.
3. Reproduce ForkFront windows, status, messages, menus, questions, and custom keyboard.
4. Translate `NHW_Map.java` touch state machine: press, long press, pan, pinch, pointer transitions, coordinate conversion, and cancellation. Match preferences and thresholds rather than assuming default iOS recognizers behave identically.
5. Implement writable sandbox data directories, save/restore, and lifecycle handling. Do not rely on app termination callbacks to save.
6. Compare Android/iPhone screens and touch sequences; verify new game, movement, inventory, targeting, save/relaunch, rotation, and interrupted gestures.

Installation success alone does not validate any of these remaining items.
