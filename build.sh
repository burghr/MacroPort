#!/bin/zsh
# Build MacroPort.app in ./build.
# With --run, also stop the running copy, then open the new build.
set -euo pipefail
cd "$(dirname "$0")"

swift build -c release
BIN="$(swift build -c release --show-bin-path)/MacroPort"

APP=build/MacroPort.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/MacroPort"
# To change the icon, edit Scripts/make-icon.swift, then run: swift Scripts/make-icon.swift
cp Resources/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"
cat > "$APP/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key><string>MacroPort</string>
    <key>CFBundleIdentifier</key><string>com.coconetlabs.macroport</string>
    <key>CFBundleExecutable</key><string>MacroPort</string>
    <key>CFBundleIconFile</key><string>AppIcon</string>
    <key>CFBundlePackageType</key><string>APPL</string>
    <key>CFBundleShortVersionString</key><string>1.0.0</string>
    <key>LSMinimumSystemVersion</key><string>14.0</string>
    <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST
# The app is not sandboxed. It must read and write the preferences file of
# another app, which a sandboxed app cannot do.
codesign --force --sign - "$APP"
touch "$APP"
echo "Built $APP"

if [[ "${1:-}" == "--run" ]]; then
    if pkill -TERM -f "MacroPort.app/Contents/MacOS/MacroPort"; then
        for _ in {1..50}; do pgrep -f "MacroPort.app/Contents/MacOS/MacroPort" >/dev/null || break; sleep 0.1; done
    fi
    open "$APP"
    echo "Opened $APP"
fi
