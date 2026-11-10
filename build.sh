#!/bin/sh
# build.sh: Sound Recorder (Mantra).app, swiftc straight, no Xcode, signed "Mantra Apps"
# (MANTRA_MANIFEST mac-app-signing.md), installed in /Applications (swift-apps.md).
set -e
cd "$(dirname "$0")"
V=$(sed -n 's/^let VERSION = \([0-9]*\)/\1/p' app/App.swift)
NAME="Sound Recorder (Mantra)"
APP="build/$NAME.app"
rm -rf "$APP"; mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
swiftc -O -swift-version 5 -parse-as-library -o "$APP/Contents/MacOS/MantraSoundRecorder" app/*.swift 2>&1 | grep -v "warning:" || true
[ -x "$APP/Contents/MacOS/MantraSoundRecorder" ] || { echo "the app did not build"; exit 1; }
cat > "$APP/Contents/Info.plist" <<PL
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>$NAME</string>
<key>CFBundleDisplayName</key><string>$NAME</string>
<key>CFBundleIconFile</key><string>AppIcon</string>
<key>CFBundleIdentifier</key><string>community.auroville.mantrasoundrecorder</string>
<key>CFBundleExecutable</key><string>MantraSoundRecorder</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>$V</string>
<key>CFBundleVersion</key><string>$V</string>
<key>LSMinimumSystemVersion</key><string>14.0</string>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Sound Recorder (Mantra) takes the sound of Firefox (a Suno song) without changing the Mac audio.</string>
<key>NSMicrophoneUsageDescription</key><string>Sound Recorder (Mantra) records the input you choose. The recording stays in memory and is gone when the app quits.</string>
</dict></plist>
PL
# the icon, drawn with the version under it
swift icon/make_icon.swift "$V" icon/icon_1024.png
I=build/AppIcon.iconset; rm -rf $I; mkdir -p $I
for s in 16 32 128 256 512; do
  sips -z $s $s icon/icon_1024.png --out $I/icon_${s}x${s}.png >/dev/null
  sips -z $((s*2)) $((s*2)) icon/icon_1024.png --out $I/icon_${s}x${s}@2x.png >/dev/null
done
iconutil -c icns $I -o "$APP/Contents/Resources/AppIcon.icns"
codesign --force -s "Mantra Apps" "$APP"
rm -rf "/Applications/$NAME.app"; cp -R "$APP" /Applications/
echo "built $APP (v$V) and installed it in /Applications"
# v4: the running copy quit through Accessibility, the new one opened (tools/relaunch.swift); --no-run skips it
[ "$1" = "--no-run" ] || swift tools/relaunch.swift community.auroville.mantrasoundrecorder "/Applications/$NAME.app" || true
