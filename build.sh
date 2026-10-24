#!/bin/zsh
# Builds Pulsar.app from source into ./build/Pulsar.app.
# Needs: macOS 26 (Tahoe) on Apple silicon, and the Xcode Command Line Tools (xcode-select --install).
# A build from source has every part unlocked: no license key, no trial, no update checks.
set -e
cd "$(dirname "$0")"

APP="build/Pulsar.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"

# Info.plist without the demo URL scheme. Change CFBundleIdentifier in Info.plist to your own if you like.
cp Info.plist "$APP/Contents/Info.plist"
/usr/libexec/PlistBuddy -c "Delete :CFBundleURLTypes" "$APP/Contents/Info.plist" 2>/dev/null || true

# Resources: key sounds, the Claude Code hook, the icon, third-party licenses
cp -R sounds "$APP/Contents/Resources/sounds"
cp agente/hook.py "$APP/Contents/Resources/hook.py"
cp assets/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
mkdir -p "$APP/Contents/Resources/Licenze"
cp Vendor/libwebp/COPYING "$APP/Contents/Resources/Licenze/libwebp.txt"
cp Vendor/Sparkle/LICENSE "$APP/Contents/Resources/Licenze/Sparkle.txt"
# Sparkle is linked but stays off: a source build has no update feed in its Info.plist.
ditto Vendor/Sparkle/Sparkle.framework "$APP/Contents/Frameworks/Sparkle.framework"

source ./sorgenti.sh
KIT="build/rowline-kit"
kit_rowline "$KIT" -O -D DA_SORGENTE
swiftc -O -D DA_SORGENTE ${=$(kit_flag "$KIT")} ${=LIBRERIE} $SPARKLE $CORE $MODULI -o "$APP/Contents/MacOS/Pulsar"
xattr -cr "$APP"

# Ad-hoc signature. macOS asks for permissions again after every rebuild; to keep them, sign with a fixed
# self-signed certificate instead (Keychain Access > Certificate Assistant > Create a Certificate, type Code Signing).
codesign --force --deep --sign - "$APP"
echo "Built: $APP"
echo "Open it with: open $APP   (move it to /Applications to keep it)"
