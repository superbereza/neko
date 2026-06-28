# neko characterization tests

Characterization (golden-master) tests that pin the current behavior of the four
core subsystems in `src/neko.swift` so a later refactor can extract a pure core
without silently changing behavior. They also lock in the specific edge cases
codex flagged as risky.

## Important: the mirror is a SNAPSHOT, not the real module

`tests/NekoCoreMirror.swift` is a **characterization snapshot** — a faithful,
hand-translated **copy** of the algorithms in `src/neko.swift`:

- `CGFloat` -> `Double`
- AppKit/Cocoa/Carbon dropped (`import Foundation` only)
- `Double.random(in:)` / `Bool.random()` replaced by an injected `RandomSource`
  (`SeededRNG`, `QueueRNG`) so RNG-dependent branches are deterministic and
  consumption can be asserted

The app is **untouched** by these tests. This is deliberate: during the refactor,
the pure logic will be **extracted out of `src/neko.swift` into a real module**,
at which point `NekoCoreMirror.swift` is **deleted** and `Tests.swift` is
**retargeted** to import that real module. The golden values stay; only the
thing-under-test changes. Until then, the mirror standing in for the real core is
the whole point.

> HARD CONSTRAINT for this harness: only files under `tests/` exist here.
> `src/neko.swift` and all production/build files are never modified.

## How to run

```bash
bash tests/run.sh
```

`run.sh` compiles `NekoCoreMirror.swift` + `Tests.swift` with raw `swiftc -O`
(no Xcode, no SPM) into a temp binary and runs it. Exit code is `0` on all-pass,
`1` on any failure (the runner also prints each `FAIL:` with got/want). Last line
is `RESULT: PASS` / `RESULT: FAIL`.

Current state: `neko characterization tests: 110/110 passed, 0 failed` (exit 0).

## Files

- `run.sh` — build + run driver (raw `swiftc -O`).
- `NekoCoreMirror.swift` — the snapshot copy of the core (see note above).
- `Tests.swift` — assertion runner (`expect` / `expectEq` / `expectClose`) plus
  all scenarios, with a `@main` entry point (multi-file `swiftc` forbids
  top-level code).

## What each test characterizes (test -> `src/neko.swift` behavior)

### `testDrives()` — drives/needs (`src/neko.swift` ~451-461, 527, 717-719)
- `growHunger` = `min(1, hunger + (hungry ? 0.00022 : 0.00011))` and its clamp — line ~453.
- `driftEnergyBoredom`: sleep/walk/zoomies/idle/other drift + [0,1] clamps — lines ~456-461.
- `satiateBite` = `max(0, hunger - 0.34/maxBites)`, plus full-kibble cumulative — line ~527.
- `clampRestore` = `min(1,max(0,v))` — lines ~717-719.
  - **codex bug pinned:** old saves stored a raw counter; load must clamp
    out-of-range needs into [0,1] (`clampRestore(7.0)==1.0`).

### `testActionSelection()` — `decideNext()` (`src/neko.swift` ~374-425)
- Food override (`hunger > EAT_HUNGER && hasFood`) as an early return that consumes
  **zero RNG** (asserted via `QueueRNG` counters) — lines ~376-378.
- night/crepuscular windows, the four weight formulas, mood multipliers, weight
  order `[sleep,walk,zoomies,idle]`, `total = Σ max(0,w)`, cumulative
  `r < max(0,w)` pick, `idle` default — lines ~380-405.
- `awayChance` 0.16 (curious) / 0.07, draw order (uniform for awayChance, then
  bool for awayLeft) — lines ~408-419.
  - **codex bug pinned:** strict `>` gate — a full/low-hunger cat
    (`hunger==0.15==EAT_HUNGER`) with food present does **not** override; `0.1500001` does.
  - **codex bug pinned:** `total>0` guard always holds (idle floor 0.5) — 2000-iter
    seeded sweep + zero-weight-zoom skip always yield a valid state.

### `testFood()` — targeting & eating (`src/neko.swift` ~369-372, 376, 463-472, 519-539, 845-853)
- `pileCenter` averages **all** kibbles with **no** landed/dragging filter — lines ~369-372.
  - **codex bug pinned (THRASH):** two separated piles (x=100 and x=900) average
    to empty midpoint 500; nothing is in eat range there, yet the target keeps
    pointing back to 500.
- `decideFoodTarget` / `foodAttractor` EAT_HUNGER gate is strict `>` in **both**
  paths (`hunger==0.15` rejected, `0.150001` admitted) — lines ~376, 464.
- `inEatRange` inclusive `<= SIZE/2 (==32)` — lines ~521, 847.
- `eatNearbyKibbleIndex` = top-most (max y) landed in-range, ignores non-landed — lines ~845-848.
- `applyBite` / `biteStage` stages (1,2,3,3 for maxBites=4; clamp at maxBites=3) — lines ~524-535.
- `foodAttractor` suppressed while eating / goingAway / leaving; `.none` from
  sleep, `.retargetWalk` from walk, `.startWalk` from idle/zoomies — lines ~463-472.
- `canKeepEating` breaks on drag / unlanded / out-of-range — lines ~519-521.

### `testKibblePhysics()` — `updateKibbles()` (`src/neko.swift` ~787-842)
- Stability pre-pass requiring support on **both** sides (`abs(o.y+8-k.y)<5`,
  `<11` x-window), in-place unland — lines ~793-798.
- Integration: `vy-=2.2`, `vx*=0.99`, escape removal (off top / ±40 / maxY+150),
  wall clamp at HALF=7 with 0.5/0.4 restitution, hard-impact (`-vy>3 -> *-0.32`)
  bounce, floor settle (`abs(vx)<0.4 -> landed`), single-support slide `±2.2` with
  tie-break, ground friction `*0.85` near base — lines ~799-841.
  - Hard-impact golden `vx=1.0098` = `1.98·0.6·0.85`.
  - **codex bug pinned:** removing a pile's support collapses the top kibble
    (stability pass unlands, then it slides off).
  - **codex bug pinned:** tie-break slide direction is deterministic via injected
    `randBool` (no AppKit `Bool.random()`): `true`->+dir (x=102.2), `false`->-dir (x=97.8).

### `testRepeatedRetarget()` — attractor follow + restore clamp
- **codex bug pinned (repeated walk-target changes):** while walking+hungry the
  attractor recomputes the target to the live pile center every tick; a drifting
  pile yields targets `200,250,300,350,400` (`src/neko.swift` ~464-466).
- Restore clamps out-of-range needs into [0,1] on load (`clampRestore`).

> Line numbers are approximate anchors against the snapshotted `src/neko.swift`;
> after extraction they retarget to the real pure module.
