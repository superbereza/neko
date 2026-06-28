#!/bin/bash
# Собрать и установить Neko в /Applications
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./build.sh
pkill -f '/Applications/Neko.app/Contents/MacOS/Neko' 2>/dev/null || true
sleep 0.4
rm -rf /Applications/Neko.app
cp -R dist/Neko.app /Applications/Neko.app
codesign --force --deep --sign - /Applications/Neko.app 2>/dev/null || true
echo "Установлено: /Applications/Neko.app"
