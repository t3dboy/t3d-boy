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

# --- Vendored rcheevos (RetroAchievements C runtime) ---
# Compiled once into a cached static lib (rebuild: rm build/librcheevos.a).
RC=vendor/rcheevos
RCLIB=build/librcheevos.a
if [ ! -f "$RCLIB" ]; then
    echo "== Compiling rcheevos =="
    rm -rf build/rcobj && mkdir -p build/rcobj
    RCCFLAGS="-O2 -DRC_DISABLE_LUA -DRC_CLIENT_SUPPORTS_HASH -I$RC/include -I$RC/src -I$RC/src/rcheevos -I$RC/src/rapi -I$RC/src/rhash"
    RCOBJS=""
    for c in $(find "$RC/src" -name '*.c' | grep -vE 'rc_libretro.c|rc_client_external.c'); do
        o="build/rcobj/$(echo "$c" | tr '/' '_').o"
        xcrun clang $RCCFLAGS -c "$c" -o "$o"
        RCOBJS="$RCOBJS $o"
    done
    ar rcs "$RCLIB" $RCOBJS
    rm -rf build/rcobj
fi

# Local dev builds opt in with T3DBOY_DEV_BUILD=1, which compiles in the insecure
# plaintext token store (gated again at runtime by T3DBOY_DEV_TOKEN) so unattended
# rebuild loops don't hit the Keychain prompt. A normal/release build omits -D DEV,
# so the dev store isn't in the binary at all.
DEVFLAG=()
if [ "${T3DBOY_DEV_BUILD:-}" = "1" ]; then
    echo "== DEV build: plaintext dev token store ENABLED (do not ship) =="
    DEVFLAG=(-D DEV)
fi

echo "== Compiling T3d Boy ${VERSION} =="
xcrun swiftc -O -swift-version 5 -o "$APP/Contents/MacOS/T3d Boy" \
    ${DEVFLAG[@]+"${DEVFLAG[@]}"} \
    $(find Sources -name '*.swift') \
    -framework Cocoa -framework AVFoundation -framework GameController \
    -Xcc -fmodule-map-file="$RC/include/module.modulemap" -Xcc -I"$RC/include" \
    -Xcc -DRC_DISABLE_LUA -Xcc -DRC_CLIENT_SUPPORTS_HASH \
    "$RCLIB" -lz
cp Info.plist "$APP/Contents/Info.plist"

# Stamp the version into the bundle from VERSION
/usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString ${VERSION}" "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VERSION}" "$APP/Contents/Info.plist"

echo "== Icon =="
# Source of truth is the committed tools/AppIcon.png. Keep an existing build/AppIcon.png
# (so live edits aren't clobbered); on a clean build, restore from the committed source,
# falling back to generating one only if neither exists.
if [ ! -f build/AppIcon.png ]; then
    if [ -f tools/AppIcon.png ]; then
        cp tools/AppIcon.png build/AppIcon.png
    else
        xcrun swift tools/makeicon.swift build/AppIcon.png
    fi
fi
ICONSET=build/AppIcon.iconset
rm -rf "$ICONSET" && mkdir -p "$ICONSET"
for s in 16 32 128 256 512; do
    sips -z $s $s build/AppIcon.png --out "$ICONSET/icon_${s}x${s}.png" >/dev/null
    d=$((s * 2))
    sips -z $d $d build/AppIcon.png --out "$ICONSET/icon_${s}x${s}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "== Signing (ad-hoc, hardened runtime) =="
# Hardened runtime hardens the process against debugger attach / memory scraping
# (which matters because the RA password/token live in process memory transiently)
# and is a prerequisite for notarization. Ad-hoc signing supports it; for a public
# release, re-sign with a Developer ID identity and notarize.
codesign --force --options runtime --sign - "$APP"

# Re-register the freshly built bundle with LaunchServices so the Dock and Finder
# pick up the current icon instead of a stale cached one. Rebuilding an unsigned
# bundle in place repeatedly otherwise leaves macOS showing an old/generic icon.
echo "== Refreshing icon registration =="
touch "$APP"
LSREGISTER=/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister
[ -x "$LSREGISTER" ] && "$LSREGISTER" -f "$APP" >/dev/null 2>&1 || true

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
