#!/bin/bash
# Упаковать Neko.app в DMG (с ярлыком Applications для drag-install)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
[ -d dist/Neko.app ] || ./build.sh
STAGE="$(mktemp -d)/Neko"
mkdir -p "$STAGE"
cp -R dist/Neko.app "$STAGE/"
ln -s /Applications "$STAGE/Applications"
rm -f dist/Neko.dmg
hdiutil create -volname "Neko" -srcfolder "$STAGE" -ov -format UDZO dist/Neko.dmg >/dev/null
echo "Готово: $ROOT/dist/Neko.dmg"
