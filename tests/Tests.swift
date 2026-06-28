// Tests.swift
//
// Characterization tests for the neko desktop-pet core algorithms, run against
// the pure mirror in NekoCoreMirror.swift. The mirror is a faithful copy of
// src/neko.swift — src/neko.swift is never touched.
//
// Covers every golden scenario from the 4 subsystem specs plus the codex risky
// cases (two separated piles, full cat with food, hunger gate in both paths,
// removed support collapse, repeated walk-target changes, restore clamps,
// weighted-pick total>0 guard).

import Foundation

// MARK: - Tiny assert-based runner -------------------------------------------

var passCount = 0
var failCount = 0
let EPS = 1e-9

func expect(_ cond: Bool, _ name: String) {
    if cond { passCount += 1 }
    else { failCount += 1; print("FAIL: \(name)") }
}

func expectEq<T: Equatable>(_ got: T, _ want: T, _ name: String) {
    if got == want { passCount += 1 }
    else { failCount += 1; print("FAIL: \(name)\n      got:  \(got)\n      want: \(want)") }
}

func expectClose(_ got: Double, _ want: Double, _ name: String, tol: Double = EPS) {
    if abs(got - want) <= tol { passCount += 1 }
    else { failCount += 1; print("FAIL: \(name)\n      got:  \(got)\n      want: \(want)  (|d|=\(abs(got-want)))") }
}

// =====================================================================
// 1) DRIVES / NEEDS
// =====================================================================
func testDrives() {
    expectClose(growHunger(0.5, mood: .normal), 0.5 + HUNGER_STEP_NORMAL, "drives: hunger growth normal one tick")
    expectClose(growHunger(0.5, mood: .hungry), 0.5 + HUNGER_STEP_HUNGRY, "drives: hunger growth hungry one tick")
    expectClose(growHunger(1.0, mood: .normal), 1.0, "drives: hunger growth clamps at 1")

    var d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.7, boredom: 0.3), state: .sleep)
    expectClose(d.energy, 0.7008, "drives: energy rises in sleep")
    expectClose(d.boredom, 0.3004, "drives: boredom rises in sleep")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.9996, boredom: 0.3), state: .sleep)
    expectClose(d.energy, 1.0, "drives: energy clamps at 1 in sleep")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.5, boredom: 0.5), state: .walk)
    expectClose(d.energy, 0.4984, "drives: energy drains while walking")
    expectClose(d.boredom, 0.4975, "drives: boredom drops while walking")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.001, boredom: 0.5), state: .zoomies)
    expectClose(d.energy, 0.0, "drives: energy clamps at 0 (zoomies = walk branch)")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.5, boredom: 0.001), state: .walk)
    expectClose(d.boredom, 0.0, "drives: boredom clamps at 0 while moving")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.4, boredom: 0.4), state: .idle)
    expectClose(d.energy, 0.4003, "drives: idle energy drift")
    expectClose(d.boredom, 0.4007, "drives: idle boredom drift")

    d = driftEnergyBoredom(Drives(hunger: 0, energy: 0.4, boredom: 0.4), state: .other)
    expectClose(d.energy, 0.4, "drives: no energy drift in other state")
    expectClose(d.boredom, 0.4, "drives: no boredom drift in other state")

    let t = tickDrives(Drives(hunger: 0.2, energy: 0.5, boredom: 0.5), state: .walk, mood: .normal)
    expectClose(t.hunger, 0.2 + HUNGER_STEP_NORMAL, "drives: combined tick walk hunger")
    expectClose(t.energy, 0.4984, "drives: combined tick walk energy")
    expectClose(t.boredom, 0.4975, "drives: combined tick walk boredom")

    expectClose(satiateBite(0.5, maxBites: 4), 0.5 - SATIATION/4.0, "drives: satiation per bite maxBites=4")
    expectClose(satiateBite(0.5, maxBites: 3), 0.5 - SATIATION/3.0, "drives: satiation per bite maxBites=3")
    expectClose(satiateBite(0.0, maxBites: 4), 0.0, "drives: satiation clamps at 0")

    var h = 0.5
    for _ in 0..<4 { h = satiateBite(h, maxBites: 4) }
    expectClose(h, 0.5 - SATIATION, "drives: full kibble eaten maxBites=4 removes SATIATION")

    expectClose(clampRestore(1.5), 1.0, "drives: restore clamps high value")
    expectClose(clampRestore(-0.2), 0.0, "drives: restore clamps negative")
    expectClose(clampRestore(0.42), 0.42, "drives: restore passes in-range value")
    expectClose(clampRestore(7.0), 1.0, "drives: restore repairs old raw-counter save")
}

// =====================================================================
// 2) ACTION SELECTION — decideNext()
// =====================================================================
func testActionSelection() {
    // food override beats everything; no RNG consumed.
    var rng = QueueRNG(uniforms: [], bools: [])
    var dec = chooseAction(needs: Needs(hunger: 0.9, energy: 0.2, boredom: 0.9),
                           hour: 3, mood: .lazy, hasFood: true, rng: &rng)
    expectEq(dec, Decision(state: .walk, toFood: true), "action: food override beats everything")
    expect(rng.uniformsConsumed == 0 && rng.boolsConsumed == 0, "action: food override consumes no RNG")

    // food override suppressed when no kibble -> falls through to weights.
    rng = QueueRNG(uniforms: [0.5])
    dec = chooseAction(needs: Needs(hunger: 0.5, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .sleep), "action: food override suppressed when no kibble")

    // weighted pick = sleep
    rng = QueueRNG(uniforms: [0.5])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .sleep), "action: weighted pick = sleep")

    // weighted pick = walk, stays on screen
    rng = QueueRNG(uniforms: [1.5, 0.5])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .walk), "action: weighted pick = walk stays on screen")

    // weighted pick = walk, wanders away (uniform 0.01 < 0.07, bool true)
    rng = QueueRNG(uniforms: [1.5, 0.01], bools: [true])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .walk, goingAway: true, awayLeft: true),
             "action: weighted pick = walk wanders away")

    // curious raises awayChance to 0.16
    rng = QueueRNG(uniforms: [2.0, 0.10], bools: [false])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .curious, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .walk, goingAway: true, awayLeft: false),
             "action: curious raises awayChance to 0.16")

    // night term dominates -> sleep
    rng = QueueRNG(uniforms: [2.0])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 0.2, boredom: 0.5),
                       hour: 3, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .sleep), "action: night term dominates -> sleep")

    // crepuscular + playful -> zoomies
    rng = QueueRNG(uniforms: [4.0])
    dec = chooseAction(needs: Needs(hunger: 0.5, energy: 0.9, boredom: 0.9),
                       hour: 19, mood: .playful, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .zoomies), "action: crepuscular + playful -> zoomies")

    // zero-weight zoom skipped; idle floor keeps total>0
    rng = QueueRNG(uniforms: [1.7])
    dec = chooseAction(needs: Needs(hunger: 0.0, energy: 1.0, boredom: 0.0),
                       hour: 12, mood: .normal, hasFood: false, rng: &rng)
    expectEq(dec, Decision(state: .idle), "action: zero-weight zoom skipped, total>0 guard")

    // --- codex risky: full cat (low hunger) with food present does NOT override ---
    rng = QueueRNG(uniforms: [0.5])
    dec = chooseAction(needs: Needs(hunger: EAT_HUNGER, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: true, rng: &rng)
    expect(dec.toFood == false, "action: hunger==EAT_HUNGER does NOT trigger food override (strict >)")

    rng = QueueRNG(uniforms: [0.5])
    dec = chooseAction(needs: Needs(hunger: EAT_HUNGER + 0.0000001, energy: 0.7, boredom: 0.3),
                       hour: 12, mood: .normal, hasFood: true, rng: &rng)
    expectEq(dec, Decision(state: .walk, toFood: true), "action: hunger just above gate DOES override to food")

    // --- codex risky: weighted pick with total>0 guard via deterministic RNG ---
    var seeded = SeededRNG(seed: 12345)
    var sawNonIdleFallback = true
    for _ in 0..<2000 {
        let d = chooseAction(needs: Needs(hunger: 0.3, energy: 0.5, boredom: 0.5),
                             hour: 12, mood: .normal, hasFood: false, rng: &seeded)
        // total is always > 0 (wIdle floor 0.5), so a state is always cumulatively chosen.
        if ![CatState.sleep, .walk, .zoomies, .idle].contains(d.state) { sawNonIdleFallback = false }
    }
    expect(sawNonIdleFallback, "action: seeded sweep always yields a valid state (total>0 guard holds)")
}

// =====================================================================
// 3) FOOD TARGETING & EATING
// =====================================================================
func testFood() {
    expect(pileCenter([]) == nil, "food: pileCenter empty == nil")
    expectClose(pileCenter([Kibble(x: 300)])!, 300.0, "food: pileCenter single")
    expectClose(decideFoodTarget(hunger: 0.9, kibbles: [Kibble(x: 300)])!, 300.0,
                "food: decideFoodTarget single")

    // EAT_HUNGER gate strict >
    expect(decideFoodTarget(hunger: EAT_HUNGER, kibbles: [Kibble(x: 300)]) == nil,
           "food: gate strict > rejects hunger==EAT_HUNGER")
    expectClose(decideFoodTarget(hunger: EAT_HUNGER + 0.000001, kibbles: [Kibble(x: 300)])!, 300.0,
                "food: gate admits hunger just above EAT_HUNGER")

    // codex risky: THRASH two separated piles -> empty midpoint
    var ks: [Kibble] = []
    for _ in 0..<5 { ks.append(Kibble(x: 100, landed: true)) }
    for _ in 0..<5 { ks.append(Kibble(x: 900, landed: true)) }
    let center = pileCenter(ks)!
    expectClose(center, 500.0, "food: THRASH two piles -> midpoint 500")
    expect(eatNearbyKibbleIndex(catX: center, kibbles: ks) == nil,
           "food: THRASH nothing in eat range at midpoint")
    // hunger stays above gate => target keeps pointing to empty midpoint (documented thrash)
    expectClose(decideFoodTarget(hunger: 0.9, kibbles: ks)!, 500.0,
                "food: THRASH cat keeps returning to empty midpoint")

    // eat-range boundary inclusive
    expect(inEatRange(kibbleX: 332, catX: 300) == true, "food: eat range 32 inclusive")
    expect(inEatRange(kibbleX: 333, catX: 300) == false, "food: eat range 33 excluded")

    // eatNearbyKibble picks top-most
    let pick = [Kibble(x: 290, y: 0, landed: true),
                Kibble(x: 305, y: 8, landed: true),
                Kibble(x: 295, y: 4, landed: true)]
    expectEq(eatNearbyKibbleIndex(catX: 300, kibbles: pick), 1, "food: eatNearbyKibble picks top-most")

    // ignores non-landed
    let mix = [Kibble(x: 300, y: 8, landed: false),
               Kibble(x: 300, y: 0, landed: true)]
    expectEq(eatNearbyKibbleIndex(catX: 300, kibbles: mix), 1, "food: eatNearbyKibble ignores non-landed")

    // single bite maxBites=4
    var br = applyBite(hunger: 0.9, kibble: Kibble(x: 0, eaten: 0, maxBites: 4))
    expectClose(br.hunger, 0.9 - SATIATION/4.0, "food: single bite hunger maxBites=4")
    expectEq(br.kibble.eaten, 1, "food: single bite eaten=1")
    expectEq(br.stage, 1, "food: single bite stage=1")
    expect(br.finished == false, "food: single bite not finished")

    // full kibble consumed maxBites=4 (track stages 1,2,3,3)
    var k = Kibble(x: 0, eaten: 0, maxBites: 4)
    var hunger = 0.9
    var stages: [Int] = []
    var finished = false
    for _ in 0..<4 {
        br = applyBite(hunger: hunger, kibble: k)
        hunger = br.hunger; k = br.kibble; stages.append(br.stage); finished = br.finished
    }
    expectClose(hunger, 0.9 - SATIATION, "food: full kibble hunger drops by SATIATION")
    expectEq(stages, [1, 2, 3, 3], "food: full kibble stages 1,2,3,3")
    expect(finished, "food: full kibble finished on 4th bite")

    // hunger floor at zero
    br = applyBite(hunger: 0.0, kibble: Kibble(x: 0, eaten: 0, maxBites: 4))
    expectClose(br.hunger, 0.0, "food: hunger floor at zero")

    // biteStage maxBites=3
    expectEq(biteStage(eaten: 1, maxBites: 3), 1, "food: biteStage m3 eaten1")
    expectEq(biteStage(eaten: 2, maxBites: 3), 2, "food: biteStage m3 eaten2")
    expectEq(biteStage(eaten: 3, maxBites: 3), 3, "food: biteStage m3 eaten3 clamped")

    // attractor leaves sleep/away untouched; walk/idle/zoomies act
    let one = [Kibble(x: 200, landed: true)]
    expectEq(foodAttractor(state: "sleep", hunger: 0.9, eating: false, goingAway: false, leaving: false, kibbles: one),
             .none, "food: attractor leaves sleep untouched")
    expectEq(foodAttractor(state: "walk", hunger: 0.9, eating: false, goingAway: false, leaving: false, kibbles: one),
             .retargetWalk(200), "food: attractor retargets walk")
    expectEq(foodAttractor(state: "idle", hunger: 0.9, eating: false, goingAway: false, leaving: false, kibbles: one),
             .startWalk(200), "food: attractor starts walk from idle")
    expectEq(foodAttractor(state: "zoomies", hunger: 0.9, eating: false, goingAway: false, leaving: false, kibbles: one),
             .startWalk(200), "food: attractor starts walk from zoomies")

    // attractor suppressed while eating / goingAway / leaving
    expectEq(foodAttractor(state: "idle", hunger: 0.9, eating: true, goingAway: false, leaving: false, kibbles: one),
             .none, "food: attractor suppressed while eating")
    expectEq(foodAttractor(state: "idle", hunger: 0.9, eating: false, goingAway: true, leaving: false, kibbles: one),
             .none, "food: attractor suppressed while goingAway")
    expectEq(foodAttractor(state: "idle", hunger: 0.9, eating: false, goingAway: false, leaving: true, kibbles: one),
             .none, "food: attractor suppressed while leaving")

    // codex risky: hunger gate in attractor too
    expectEq(foodAttractor(state: "idle", hunger: EAT_HUNGER, eating: false, goingAway: false, leaving: false, kibbles: one),
             .none, "food: attractor gate strict > rejects hunger==EAT_HUNGER")

    // keep-eating guard breaks on drag / unlanded / out-of-range
    expect(canKeepEating(Kibble(x: 300, landed: true, dragging: true), catX: 300) == false,
           "food: keep-eating breaks on drag")
    expect(canKeepEating(Kibble(x: 300, landed: false), catX: 300) == false,
           "food: keep-eating breaks when unlanded")
    expect(canKeepEating(Kibble(x: 400, landed: true), catX: 300) == false,
           "food: keep-eating breaks out of range")
    expect(canKeepEating(Kibble(x: 320, landed: true), catX: 300) == true,
           "food: keep-eating stays valid in range")
}

// =====================================================================
// 4) KIBBLE PHYSICS — stepKibbles()
// =====================================================================
func testKibblePhysics() {
    let w = World(minX: 0, maxX: 1000, minY: 0, maxY: 900)

    // Free fall, no support
    var out = stepKibbles([Kibble(x: 100, y: 500)], world: w)
    expect(out.count == 1, "physics: free fall still present")
    expectClose(out[0].x, 100, "physics: free fall x")
    expectClose(out[0].y, 497.8, "physics: free fall y")
    expectClose(out[0].vx, 0, "physics: free fall vx")
    expectClose(out[0].vy, -2.2, "physics: free fall vy")
    expect(out[0].landed == false, "physics: free fall not landed")

    // Gentle landing on floor
    out = stepKibbles([Kibble(x: 100, y: 1, vx: 0.2, vy: -0.5)], world: w)
    expectClose(out[0].x, 100.198, "physics: gentle landing x")
    expectClose(out[0].y, 0, "physics: gentle landing y")
    expectClose(out[0].vx, 0, "physics: gentle landing vx")
    expectClose(out[0].vy, 0, "physics: gentle landing vy")
    expect(out[0].landed == true, "physics: gentle landing landed")

    // Hard floor impact bounces
    out = stepKibbles([Kibble(x: 100, y: 1, vx: 2, vy: -5)], world: w)
    expectClose(out[0].x, 101.98, "physics: hard impact x")
    expectClose(out[0].y, 0, "physics: hard impact y")
    expectClose(out[0].vy, 2.304, "physics: hard impact vy")
    expectClose(out[0].vx, 1.0098, "physics: hard impact vx (after ground friction)")
    expect(out[0].landed == false, "physics: hard impact still airborne")

    // canEscape removal off top
    out = stepKibbles([Kibble(x: 100, y: 800, vy: 300, canEscape: true)], world: w)
    expect(out.isEmpty, "physics: canEscape removal off top")

    // Stable pit stays put
    let pit = [Kibble(x: 100, y: 8, landed: true),
               Kibble(x: 94, y: 0, landed: true),
               Kibble(x: 106, y: 0, landed: true)]
    out = stepKibbles(pit, world: w)
    expect(out.count == 3, "physics: stable pit count")
    expect(out[0].landed && out[0].x == 100 && out[0].y == 8, "physics: stable pit k0 unchanged")
    expect(out[1] == pit[1] && out[2] == pit[2], "physics: stable pit supports unchanged")

    // Single-support collapse and slide-off (stability pass unlands, then slides)
    let single = [Kibble(x: 100, y: 8, landed: true),
                  Kibble(x: 94, y: 0, landed: true)]
    out = stepKibbles(single, world: w)
    expect(out[0].landed == false, "physics: single-support k0 unlands")
    expectClose(out[0].x, 102.2, "physics: single-support slide x")
    expectClose(out[0].y, 6, "physics: single-support slide y")
    expectClose(out[0].vy, 0, "physics: single-support slide vy")
    expectClose(out[0].vx, 0, "physics: single-support slide vx")
    expect(out[1] == single[1], "physics: single-support support unchanged")

    // Wall bounce when not escaping
    out = stepKibbles([Kibble(x: 5, y: 500, vx: -10, vy: 0, canEscape: false)], world: w)
    expectClose(out[0].x, 7, "physics: wall bounce x clamped")
    expectClose(out[0].y, 497.8, "physics: wall bounce y")
    expectClose(out[0].vx, 4.95, "physics: wall bounce vx reflected")
    expectClose(out[0].vy, -2.2, "physics: wall bounce vy")
    expect(out[0].landed == false, "physics: wall bounce not landed")

    // codex risky: removed support in a pile collapses (pile of 3 stacked, remove middle base)
    // Build a 2-high stack supported by two bases; remove one base -> top should unland next tick.
    let collapse = [Kibble(x: 100, y: 8, landed: true),   // top
                    Kibble(x: 95, y: 0, landed: true)]    // only one base remains
    out = stepKibbles(collapse, world: w)
    expect(out[0].landed == false, "physics: removed support -> top kibble collapses (unlands)")

    // codex risky: deterministic tie slide uses injected randBool (no AppKit Bool.random)
    let tie = [Kibble(x: 100, y: 8, landed: false, canEscape: false), // exactly above support
               Kibble(x: 100, y: 0, landed: true)]
    out = stepKibbles(tie, world: w, randBool: { true })
    // dx==0 tie -> dir = +1, slides right by 2.2 from x=100
    expectClose(out[0].x, 102.2, "physics: tie slide uses injected randBool=true -> +dir")
    out = stepKibbles(tie, world: w, randBool: { false })
    expectClose(out[0].x, 97.8, "physics: tie slide uses injected randBool=false -> -dir")
}

// =====================================================================
// Extra codex risky: repeated walk-target changes (attractor keeps retargeting)
// =====================================================================
func testRepeatedRetarget() {
    // While walking and hungry, the attractor recomputes the target every tick
    // to the current pile center. Moving the pile each tick must keep retargeting.
    var piles = [Kibble(x: 200, landed: true)]
    var targets: [Double] = []
    for step in 0..<5 {
        let a = foodAttractor(state: "walk", hunger: 0.9, eating: false,
                              goingAway: false, leaving: false, kibbles: piles)
        if case let .retargetWalk(c) = a { targets.append(c) }
        piles[0].x += 50            // pile drifts; cat must follow
        _ = step
    }
    expectEq(targets, [200, 250, 300, 350, 400], "retarget: walk attractor follows moving pile each tick")

    // codex risky: restore clamps out-of-range needs (old raw-counter saves)
    let restored = Drives(hunger: clampRestore(7.0),
                          energy: clampRestore(-3.0),
                          boredom: clampRestore(0.42))
    expectEq(restored, Drives(hunger: 1.0, energy: 0.0, boredom: 0.42),
             "restore: out-of-range needs clamped into [0,1]")
}

// MARK: - main ---------------------------------------------------------------

@main
struct TestMain {
    static func main() {
        testDrives()
        testActionSelection()
        testFood()
        testKibblePhysics()
        testRepeatedRetarget()

        let total = passCount + failCount
        print("------------------------------------------------")
        print("neko characterization tests: \(passCount)/\(total) passed, \(failCount) failed")
        if failCount > 0 {
            print("RESULT: FAIL")
            exit(1)
        } else {
            print("RESULT: PASS")
            exit(0)
        }
    }
}
