#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/../.."
if [[ "$(uname -s)" != Darwin ]]; then
  echo 'This build requires macOS with Xcode.' >&2
  exit 1
fi
if [[ "${1:-}" == "game" ]]; then
  exec python3 sys/ios/build.py
fi
output="$(mktemp -d "${TMPDIR:-/tmp}/nethack-ios.XXXXXX")"
app="$output/Payload/NetHack.app"
mkdir -p "$app" build/ios
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
xcrun --sdk iphoneos swiftc sys/ios/App.swift -parse-as-library \
  -sdk "$sdk" -target arm64-apple-ios16.0 -O \
  -framework UIKit -framework Foundation -o "$app/NetHack"
cp sys/ios/Info.plist "$app/Info.plist"
plutil -lint "$app/Info.plist"
# SideStore signs the device build locally. No Apple credentials are used here.
(cd "$output" && /usr/bin/zip -qr NetHack-install-probe-unsigned.ipa Payload)
cp "$output/NetHack-install-probe-unsigned.ipa" build/ios/
echo 'Created build/ios/NetHack-install-probe-unsigned.ipa (installation probe, not a game build)'
