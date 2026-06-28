#!/bin/bash
# Красивый DMG в стиле кота: белый фон, чёрный пиксельный текст, Neko.app → Applications.
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
./build.sh   # всегда пересобираем, чтобы свежая иконка/код попали в DMG

mkdir -p assets dist
# фон в 1× и 2×, склеиваем в HiDPI-TIFF: чётко на Retina И ровно 600×400 точек (окно не дёргается/без скролла)
swift scripts/render-dmg-bg.swift assets/dmgbg.png   1 >/dev/null
swift scripts/render-dmg-bg.swift assets/dmgbg@2x.png 2 >/dev/null
tiffutil -cathidpicheck assets/dmgbg.png assets/dmgbg@2x.png -out assets/dmgbg.tiff >/dev/null

# иконка тома (пиксельный жёсткий диск) → assets/volicon.icns
swift scripts/render-volicon.swift assets/volicon_1024.png >/dev/null
VSET="$(mktemp -d)/vol.iconset"; mkdir -p "$VSET"
for sz in 16 32 64 128 256 512; do
  sips -z $sz $sz assets/volicon_1024.png --out "$VSET/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz*2)); sips -z $d $d assets/volicon_1024.png --out "$VSET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$VSET" -o assets/volicon.icns

# стейджинг: только сам .app (ссылку на Applications добавит create-dmg)
STAGE="$(mktemp -d)/stage"
mkdir -p "$STAGE"
cp -R dist/Neko.app "$STAGE/"

rm -f dist/Neko.dmg
create-dmg \
  --volname "Neko" \
  --volicon assets/volicon.icns \
  --background assets/dmgbg.tiff \
  --window-pos 200 120 \
  --window-size 600 400 \
  --icon-size 120 \
  --text-size 13 \
  --icon "Neko.app" 150 215 \
  --app-drop-link 450 215 \
  --no-internet-enable \
  dist/Neko.dmg "$STAGE" >/dev/null
echo "Готово: $ROOT/dist/Neko.dmg"
