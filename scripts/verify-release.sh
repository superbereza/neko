#!/bin/bash
# Smoke-тест артефактов релиза: проверяет dist/Neko.app, Neko.zip, Neko.dmg перед публикацией.
# Запуск: scripts/verify-release.sh [версия]   (версия по умолчанию — из src/neko.swift)
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
VER="${1:-$(grep -m1 'let VERSION' src/neko.swift | sed -E 's/.*"([0-9.]+)".*/\1/')}"
APP="dist/Neko.app"
fail() { echo "❌ verify-release: $1"; exit 1; }

# 1) .app
[ -d "$APP" ] || fail "нет $APP"
codesign --verify "$APP" 2>/dev/null || fail "codesign не проходит"
PV="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$APP/Contents/Info.plist" 2>/dev/null || echo '?')"
[ "$PV" = "$VER" ] || fail "версия в Info.plist ($PV) ≠ ожидаемой ($VER)"
[ -x "$APP/Contents/MacOS/Neko" ] || fail "нет исполняемого бинаря"
[ -f "$APP/Contents/Resources/oneko.png" ] || fail "нет oneko.png в ресурсах"

# 2) zip (для авто-апдейтера) распаковывается в валидный .app
[ -f dist/Neko.zip ] || fail "нет dist/Neko.zip"
TMP="$(mktemp -d)"; /usr/bin/ditto -x -k dist/Neko.zip "$TMP" 2>/dev/null || fail "zip не распаковался"
[ -d "$TMP/Neko.app" ] || fail "в zip нет Neko.app"; rm -rf "$TMP"

# 3) dmg монтируется и содержит Neko.app + ссылку на /Applications
[ -f dist/Neko.dmg ] || fail "нет dist/Neko.dmg"
hdiutil detach "/Volumes/Neko" >/dev/null 2>&1 || true
MP="$(hdiutil attach dist/Neko.dmg -nobrowse -noautoopen 2>/dev/null | grep -o '/Volumes/.*' | head -1)"
[ -n "$MP" ] || fail "DMG не смонтировался"
[ -d "$MP/Neko.app" ] || { hdiutil detach "$MP" >/dev/null 2>&1; fail "в DMG нет Neko.app"; }
[ -L "$MP/Applications" ] || { hdiutil detach "$MP" >/dev/null 2>&1; fail "в DMG нет ссылки на /Applications"; }
hdiutil detach "$MP" >/dev/null 2>&1 || true

# 4) фон DMG — HiDPI-TIFF с двумя представлениями (1× и 2×)
REPS="$(tiffutil -info assets/dmgbg.tiff 2>/dev/null | grep -c 'Resolution:')"
[ "${REPS:-0}" -ge 2 ] || fail "фон не HiDPI-TIFF (нужно ≥2 представления, найдено ${REPS:-0})"

echo "✅ verify-release: ок — Neko $VER (app/zip/dmg/фон в порядке)"
