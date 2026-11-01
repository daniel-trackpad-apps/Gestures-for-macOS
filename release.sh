#!/bin/bash
# Creates a distributable installer (DMG): dist/Gestures-for-macOS-<version>.dmg
# Usage (from the project folder): ./release.sh
#   If a "Developer ID Application" certificate is installed it is used for signing.
#   To also notarize with Apple: NOTARY_PROFILE="profile-name" bash release.sh
cd "$(dirname "$0")" || exit 1

NAME="Gestures for macOS"
BIN_NAME="GesturesForMacOS"
VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" Info.plist 2>/dev/null || echo "1.0")
OUT="$PWD/dist"
mkdir -p "$OUT"
STAGE="$PWD/build/stage"
APP="$STAGE/$NAME.app"
DMG="$OUT/Gestures-for-macOS-$VER.dmg"

# ---------- Build for all Macs (Apple Silicon and Intel) ----------
echo "Building version $VER… (takes a few minutes)"
FLAGS=""; BUILT=0
for TRY in "--arch arm64 --arch x86_64" \
           "--arch arm64 --arch x86_64 -Xswiftc -DNO_LIQUID_GLASS" \
           "-Xswiftc -DNO_LIQUID_GLASS"; do
  swift build -c release $TRY 2>&1 | tee build.log
  if [ "${PIPESTATUS[0]}" -eq 0 ]; then FLAGS="$TRY"; BUILT=1; break; fi
  echo ""; echo "Retrying with a different configuration…"
done
if [ "$BUILT" -ne 1 ]; then
  echo ""; echo "❌ Build failed. The full log is in build.log."
  grep -A3 "error:" build.log | head -20
  exit 1
fi
case "$FLAGS" in
  *x86_64*) echo "✔ Built for all Macs (Apple Silicon and Intel)";;
  *) echo "⚠️  Built for Apple Silicon only";;
esac
BIN="$(swift build -c release $FLAGS --show-bin-path)/$BIN_NAME"
[ -f "$BIN" ] || { echo "❌ Built binary not found: $BIN"; exit 1; }

# ---------- Assemble the app ----------
rm -rf "$STAGE"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"

ICNS="$PWD/Resources/AppIcon.icns"
if [ ! -f "$ICNS" ] && [ -f tools/make_icon.swift ]; then
  mkdir -p Resources; rm -rf build/AppIcon.iconset
  swift tools/make_icon.swift build/AppIcon.iconset 2>&1 | tail -3
  iconutil -c icns build/AppIcon.iconset -o "$ICNS" 2>&1
fi
[ -f "$ICNS" ] && cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# ---------- Signing ----------
IDS="$(security find-identity -v -p codesigning 2>/dev/null)"
DEVID=$(echo "$IDS" | grep -m1 "Developer ID Application" | sed -E 's/.*"(.*)".*/\1/')
if [ -n "$DEVID" ]; then
  echo "Signing with: $DEVID"
  codesign --force --options runtime --timestamp --sign "$DEVID" "$APP" || { echo "❌ Signing failed"; exit 1; }
  SIGNED="devid"
else
  DEV=$(echo "$IDS" | grep -m1 "Apple Development" | awk '{print $2}')
  codesign --force --sign "${DEV:--}" "$APP"
  SIGNED="local"
fi
codesign --verify --deep --strict "$APP" 2>&1 && echo "✔ Signature is valid"

# ---------- Installer image ----------
ln -s /Applications "$STAGE/Applications"
cat > "$STAGE/READ ME - Install and first launch.txt" <<'EOF_README'
Gestures for macOS
==================

Install
1. Drag "Gestures for macOS" to the Applications folder (shown next to it).
2. Open the app from Applications.

If macOS blocks the first launch
- Open System Settings → Privacy & Security, scroll down and click "Open Anyway" next to the app name.
  (Right-click the app → Open also works on some versions.)

Permissions (one time)
The app needs two permissions to detect gestures and run actions:
- System Settings → Privacy & Security → Accessibility: enable "Gestures for macOS".
- System Settings → Privacy & Security → Input Monitoring: enable "Gestures for macOS".
After granting the permissions, click "Restart" in the app window.

Usage
- "All Apps": gestures that work in every app.
- "Add App": different gestures for a specific app.
- Settings are stored in Application Support; removing the app does not delete them.
EOF_README

rm -f "$DMG"
hdiutil create -volname "$NAME" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null || { echo "❌ Creating the DMG failed"; exit 1; }
[ "$SIGNED" = "devid" ] && codesign --force --timestamp --sign "$DEVID" "$DMG"

# ---------- Notarization (optional) ----------
NOTARIZED=0
if [ "$SIGNED" = "devid" ] && [ -n "$NOTARY_PROFILE" ]; then
  echo "Submitting to Apple for notarization… (takes a few minutes)"
  if xcrun notarytool submit "$DMG" --keychain-profile "$NOTARY_PROFILE" --wait && xcrun stapler staple "$DMG"; then
    NOTARIZED=1
  else
    echo "⚠️  Notarization failed. The file was created but is not notarized."
  fi
fi

( cd "$OUT" && shasum -a 256 "$(basename "$DMG")" > "$(basename "$DMG").sha256" )

echo ""
echo "✅ Created: $DMG"
echo "   Size: $(du -h "$DMG" | cut -f1)"
if [ "$NOTARIZED" -eq 1 ]; then
  echo "   Status: signed and notarized by Apple. Ready for everyone."
elif [ "$SIGNED" = "devid" ]; then
  echo "   Status: signed but not notarized. To notarize: NOTARY_PROFILE=\"name\" bash release.sh"
else
  echo "   Status: not signed for distribution. Users will need to click \"Open Anyway\" on first launch."
  echo "   To avoid the warning you need an Apple Developer account (\$99/year)."
fi
