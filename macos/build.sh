#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT="$ROOT/release/1.1.0-preview.4/macOS"
APP="$OUTPUT/Mouse Scroll.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$OUTPUT/architectures"
cp "$ROOT/macos/Info.plist" "$APP/Contents/Info.plist"
cp "$ROOT/assets/controls/"*.png "$APP/Contents/Resources/"
cp "$ROOT/assets/Lucide-LICENSE.txt" "$APP/Contents/Resources/"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
for ARCH in arm64 x86_64; do
  xcrun swiftc -swift-version 5 -O -sdk "$SDK" -target "$ARCH-apple-macos13.0" \
    -framework AppKit -framework ApplicationServices -framework CoreGraphics -framework IOKit -framework ServiceManagement -framework CryptoKit \
    "$ROOT/macos/MouseScroll.swift" -o "$OUTPUT/architectures/$ARCH"
done
lipo -create "$OUTPUT/architectures/arm64" "$OUTPUT/architectures/x86_64" -output "$APP/Contents/MacOS/Mouse Scroll"
ICONSET="$OUTPUT/AppIcon.iconset"
mkdir -p "$ICONSET"
for SIZE in 16 32 128 256 512; do
  sips -z "$SIZE" "$SIZE" "$ROOT/assets/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}.png" >/dev/null
  DOUBLE=$((SIZE * 2))
  sips -z "$DOUBLE" "$DOUBLE" "$ROOT/assets/icon.png" --out "$ICONSET/icon_${SIZE}x${SIZE}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force --deep --sign - "$APP"
codesign --verify --deep --strict "$APP"
"$APP/Contents/MacOS/Mouse Scroll" --self-test
mkdir -p "$OUTPUT/dmg"
cp -R "$APP" "$OUTPUT/dmg/"
ln -s /Applications "$OUTPUT/dmg/Applications"
hdiutil create -volname "Mouse Scroll" -srcfolder "$OUTPUT/dmg" -ov -format UDZO "$OUTPUT/MouseScroll-macOS.dmg"
FILE="$OUTPUT/MouseScroll-macOS.dmg"
BYTES="$(stat -f%z "$FILE")"
if [ "$BYTES" -gt 10000000 ]; then echo "DMG exceeds 10 MB: $BYTES bytes"; exit 1; fi
(cd "$OUTPUT" && shasum -a 256 MouseScroll-macOS.dmg > MouseScroll-macOS.dmg.sha256)
echo "Built universal macOS app, DMG: $BYTES bytes"
