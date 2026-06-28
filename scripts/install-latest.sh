#!/bin/bash
# Скачать последнюю версию Neko с GitHub Releases и поставить в /Applications.
# Запуск:  curl -fsSL https://raw.githubusercontent.com/superbereza/neko/main/scripts/install-latest.sh | bash
set -e
REPO="superbereza/neko"

echo "Ищу последний релиз $REPO…"
URL=$(curl -fsSL "https://api.github.com/repos/$REPO/releases/latest" \
      | grep -o 'https://[^"]*Neko\.zip' | head -1)
[ -z "$URL" ] && { echo "Не нашёл Neko.zip в последнем релизе"; exit 1; }

TMP=$(mktemp -d)
echo "Качаю: $URL"
curl -fsSL -o "$TMP/Neko.zip" "$URL"
/usr/bin/ditto -x -k "$TMP/Neko.zip" "$TMP/x"
APP=$(/usr/bin/find "$TMP/x" -maxdepth 2 -name 'Neko.app' | head -1)
[ -z "$APP" ] && { echo "В архиве нет Neko.app"; exit 1; }

pkill -f 'Neko.app/Contents/MacOS/Neko' 2>/dev/null || true
sleep 1
rm -rf /Applications/Neko.app
/usr/bin/ditto "$APP" /Applications/Neko.app
/usr/bin/xattr -dr com.apple.quarantine /Applications/Neko.app 2>/dev/null || true
rm -rf "$TMP"
open /Applications/Neko.app
VER=$(/usr/bin/defaults read /Applications/Neko.app/Contents/Info CFBundleShortVersionString 2>/dev/null || echo "?")
echo "Готово. Установлена Neko $VER и запущена."
