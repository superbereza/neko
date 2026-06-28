#!/bin/bash
# Генерирует assets/neko.icns из scripts/render-icon.swift
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
mkdir -p assets
swift scripts/render-icon.swift assets/icon_1024.png
SET="$(mktemp -d)/neko.iconset"; mkdir -p "$SET"
for sz in 16 32 64 128 256 512; do
  sips -z $sz $sz assets/icon_1024.png --out "$SET/icon_${sz}x${sz}.png" >/dev/null
  d=$((sz*2)); sips -z $d $d assets/icon_1024.png --out "$SET/icon_${sz}x${sz}@2x.png" >/dev/null
done
iconutil -c icns "$SET" -o assets/neko.icns
echo "Готово: assets/neko.icns"
