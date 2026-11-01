#!/bin/bash
# Builds the app, signs it, installs it to ~/Applications and launches it.
cd "$(dirname "$0")" || exit 1

APP_NAME="Gestures for macOS"
BIN_NAME="GesturesForMacOS"

echo "Building… (the first build takes about a minute)"
EXTRA=""
swift build -c release 2>&1 | tee build.log; OK=${PIPESTATUS[0]}
if [ "$OK" -ne 0 ]; then
  echo ""; echo "Retrying without the newer system glass effect…"
  EXTRA="-Xswiftc -DNO_LIQUID_GLASS"
  swift build -c release $EXTRA 2>&1 | tee build.log; OK=${PIPESTATUS[0]}
fi
if [ "$OK" -ne 0 ]; then
  echo ""; echo "❌ Build failed. The full log is in build.log."
  grep -A3 "error:" build.log | head -20
  exit 1
fi

BIN="$(swift build -c release $EXTRA --show-bin-path)/$BIN_NAME"
APP="$PWD/build/$APP_NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/$BIN_NAME"
cp Info.plist "$APP/Contents/Info.plist"

# App icon (generated once if it does not exist yet)
ICNS="$PWD/Resources/AppIcon.icns"
if [ ! -f "$ICNS" ] && [ -f tools/make_icon.swift ]; then
  mkdir -p Resources; rm -rf build/AppIcon.iconset
  swift tools/make_icon.swift build/AppIcon.iconset 2>&1 | tail -3
  iconutil -c icns build/AppIcon.iconset -o "$ICNS" 2>&1
fi
[ -f "$ICNS" ] && cp "$ICNS" "$APP/Contents/Resources/AppIcon.icns"

# Signing: a stable certificate keeps the granted permissions between builds
HASH=$(security find-identity -v -p codesigning | grep -m1 "Apple Development" | awk '{print $2}')
if [ -n "$HASH" ]; then SIGN="$HASH"
else SIGN="-"; echo "⚠️  No signing certificate found. Permissions may need to be granted again after every build."; fi
codesign --force --sign "$SIGN" "$APP" 2>&1

pkill -x "$BIN_NAME" 2>/dev/null
mkdir -p "$HOME/Applications"
rm -rf "$HOME/Applications/$APP_NAME.app"
cp -R "$APP" "$HOME/Applications/$APP_NAME.app"
/System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister -f "$HOME/Applications/$APP_NAME.app" 2>/dev/null
open "$HOME/Applications/$APP_NAME.app"
echo "✅ The app is installed in ~/Applications and running (it appears in the Dock)."
