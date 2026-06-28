# Neko 🐈

A calm desktop cat for macOS. It lives on the bottom edge of your screen, sleeps on a
daily rhythm, occasionally gets the zoomies, wanders around, eats kibble you sprinkle, and
sometimes willfully digs through the wall and disappears for a while. Native, zero
dependencies.

## Features

- **Needs-driven daily routine**: energy / boredom / hunger drives + time-of-day rhythm
  (sleeps deeper at night, peaks of activity at dawn and dusk — cats are crepuscular).
- **Feeding** — hold **⌃⌥⌘X** (works in any keyboard layout): kibble pours from the cursor
  with a pause; move the cursor to scatter a trail or a heap.
  - Kibble has **real physics**: gravity, mass, friction, bounce. You can **drag** and
    **throw** pieces; thrown from the upper half of the screen they fly off the edge and
    vanish.
  - Heaps **collapse**: pull out a bottom piece and the ones above tumble down (a piece
    only rests when wedged between two).
  - The cat eats the **top** pieces **bite by bite** (3–4 bites), sitting behind the heap.
    It is **not woken up** to eat — it will come once it wakes on its own.
- **Drag the cat** with the mouse (it dangles its legs and lands softly on its feet).
- **Walkabout**: every now and then it walks to the edge, digs, and leaves for 3–10 minutes,
  then comes back.
- **Auto-update** via GitHub Releases (toggle in the menu).
- Menu-bar icon is the cat's face (cut from the sprite).

## Install

Download `Neko.zip` from the [latest release](https://github.com/superbereza/neko/releases/latest),
unzip it, and move `Neko.app` to Applications. On first launch (the app isn't notarized):
right-click `Neko.app` → **Open**. After that it updates itself.

## Build & run

```bash
./build.sh            # build dist/Neko.app
open dist/Neko.app    # run
```

## Release a new version

```bash
scripts/release.sh 1.0.1 "What's new"
```
Bumps the version → builds → zips → pushes → creates a GitHub Release. Installed copies
update automatically (checked at launch and every 6 hours).

## Controls

- **⌃⌥⌘X** (hold) — pour kibble at the cursor.
- Menu-bar 🐈 → *Pour kibble*, *Go for a walk*, *Check for updates*, *Auto-update*, *Quit*.
- Drag with the mouse — both the cat and the kibble.

## Layout

```
neko/
├── README.md
├── build.sh                   # build → dist/Neko.app
├── src/neko.swift             # all the code
├── scripts/release.sh         # bump + build + zip + GitHub Release
├── scripts/render-held.swift  # helper sketcher (draft)
├── assets/oneko.png           # sprite sheet
└── dist/Neko.app              # build output (gitignored)
```

## Credits

The cat sprite is the classic **oneko** / *Neko* — a desktop pet that dates back to the
1989 Macintosh "Neko" desk accessory (Watanabe Daisuke) and the later X11 **oneko**.
The sprite sheet (`oneko.gif`) used here comes from
**[adryd325/oneko.js](https://github.com/adryd325/oneko.js)**.
All credit for the artwork goes to its original authors — this project only adds the
behaviour, physics, and macOS wrapper.
