#!/bin/bash
# Сборка Neko.app (десктоп-котик)
set -e
ROOT="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT"

APP="dist/Neko.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O src/neko.swift -o "$APP/Contents/MacOS/Neko"
cp assets/oneko.png "$APP/Contents/Resources/oneko.png"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>            <string>Neko</string>
    <key>CFBundleIdentifier</key>      <string>local.neko</string>
    <key>CFBundleExecutable</key>      <string>Neko</string>
    <key>CFBundlePackageType</key>     <string>APPL</string>
    <key>CFBundleVersion</key>         <string>1.0</string>
    <key>LSMinimumSystemVersion</key>  <string>11.0</string>
    <key>LSUIElement</key>             <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$APP" 2>/dev/null || true
echo "Готово: $APP"
