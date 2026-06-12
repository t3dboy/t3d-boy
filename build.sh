#!/bin/bash
# Builds T3d Boy.app and packages it into a versioned DMG.
# The VERSION file is the single source of truth for the release version.
set -euo pipefail
cd "$(dirname "$0")"

VERSION="$(cat VERSION 2>/dev/null || echo "0.0.0")"
APP="build/T3d Boy.app"
DMG="build/T3dBoy-${VERSION}.dmg"
rm -rf "$APP" build/dmg build/T3dBoy*.dmg
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

echo "== Compiling T3d Boy ${VERSION} =="
xcrun swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/T3d Boy" Sources/*.swift -framework Cocoa -framework AVFoundation -framework GameController
cp Info.plist "$APP/Contents/Info.plist"

# Stamp the version into the bundle from VERSION
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"

echo "== Icon =="
if [ ! -f build/AppIcon.png ]; then
    xcrun swift tools/makeicon.swift build/AppIcon.png
fi
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s build/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d build/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "== Signing (ad-hoc) =="
codesign --force --sign - "$APP"

echo "== DMG =="
mkdir -p build/dmg
cp -R "$APP" build/dmg/
ln -s /Applications build/dmg/Applications
hdiutil create -volname "T3d Boy ${VERSION}" -srcfolder build/dmg -ov -format UDZO "$DMG"
# Stable unversioned copy for convenience / local references
cp "$DMG" build/T3dBoy.dmg

# Remove transient staging; keep the .app, DMGs, and cached AppIcon.png
rm -rf build/dmg "$ICONSET"

echo "Done: $(pwd)/$DMG"
