#!/bin/bash
# Релиз новой версии Neko: bump версии → сборка → zip → GitHub Release.
# Использование: scripts/release.sh 1.0.1 "Что нового (необязательно)"
set -e
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VER="$1"
NOTES="${2:-Обновление Neko}"
if [ -z "$VER" ]; then echo "Укажи версию: scripts/release.sh 1.0.1"; exit 1; fi

# 1) проставить версию в исходник
sed -i '' -E "s/let VERSION = \"[0-9.]+\"/let VERSION = \"$VER\"/" src/neko.swift

# 2) собрать и упаковать
./build.sh >/dev/null
ditto -c -k --keepParent dist/Neko.app dist/Neko.zip

# 3) коммит и тег
git add -A
git commit -q -m "Neko $VER" || true
git push -q

# 4) релиз на GitHub (ассет Neko.zip)
gh release create "v$VER" dist/Neko.zip --title "Neko $VER" --notes "$NOTES"
echo "Готово: релиз v$VER опубликован. У пользователей обновится автоматически."
