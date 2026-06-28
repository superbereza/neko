// NekoCoreMirror.swift
//
// PURE Swift characterization mirror of the algorithms in src/neko.swift.
// This is a FAITHFUL COPY for testing only — src/neko.swift is NEVER modified.
//
// Rules honoured here:
//   * import Foundation only — NO AppKit / Cocoa / Carbon.
//   * CGFloat -> Double everywhere.
//   * Randomness is injected through a small `RandomSource` protocol so tests are
//     deterministic and reproducible (seedable SplitMix64 + a queue stub that
//     feeds the exact post-mapping uniform/bool draws the golden specs quote).
//
// Line references in comments point at the corresponding lines in src/neko.swift.

import Foundation

// MARK: - Injected randomness ------------------------------------------------

/// Semantics-faithful stand-in for the std-lib calls used in neko.swift:
///   Double.random(in: 0..<total)  ->  uniform(in: 0..<total)
///   Double.random(in: 0..<1)      ->  uniform(in: 0..<1)
///   Bool.random()                 ->  nextBool()
protocol RandomSource {
    mutating func uniform(in range: Range<Double>) -> Double
    mutating func nextBool() -> Bool
}

/// Deterministic, seedable generator (SplitMix64). Reproducible across runs.
struct SeededRNG: RandomSource {
    private var state: UInt64
    init(seed: UInt64) { state = seed }

    private mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }

    mutating func uniform(in range: Range<Double>) -> Double {
        // 53-bit fraction in [0,1), mapped into the range (same shape as stdlib).
        let frac = Double(next() >> 11) * (1.0 / 9007199254740992.0) // 1/2^53
        return range.lowerBound + frac * (range.upperBound - range.lowerBound)
    }

    mutating func nextBool() -> Bool { (next() & 1) == 0 }
}

/// Test stub: returns pre-queued, already-mapped uniform/bool draws verbatim.
/// The golden specs quote the post-mapping `r` value directly, so the queued
/// uniform value is what the algorithm sees for that draw. Consumption counters
/// let tests assert that a short-circuit (e.g. the food override) touched no RNG.
struct QueueRNG: RandomSource {
    var uniforms: [Double]
    var bools: [Bool]
    private(set) var uniformsConsumed = 0
    private(set) var boolsConsumed = 0

    init(uniforms: [Double] = [], bools: [Bool] = []) {
        self.uniforms = uniforms
        self.bools = bools
    }

    mutating func uniform(in range: Range<Double>) -> Double {
        precondition(uniformsConsumed < uniforms.count, "QueueRNG out of uniform draws")
        defer { uniformsConsumed += 1 }
        return uniforms[uniformsConsumed]
    }

    mutating func nextBool() -> Bool {
        precondition(boolsConsumed < bools.count, "QueueRNG out of bool draws")
        defer { boolsConsumed += 1 }
        return bools[boolsConsumed]
    }
}

// MARK: - Shared constants (src/neko.swift) ----------------------------------

let CELL = 32                       // neko.swift:9
let SCALE: Double = 2               // neko.swift:10
let SIZE: Double = Double(CELL) * SCALE   // 64, neko.swift:11
let SATIATION = 0.13                // neko.swift:162
let EAT_HUNGER = 0.5                // neko.swift:163
let STAGES_COUNT = 4               // KibbleDot.stages.count, neko.swift:52-57
let BITE_PERIOD = 16               // neko.swift:524
let HUNGER_STEP_NORMAL = 0.0000035    // neko.swift:453
let HUNGER_STEP_HUNGRY = 0.000007     // neko.swift:453

// =====================================================================
// MARK: 1) DRIVES / NEEDS
// =====================================================================

struct Drives: Equatable {
    var hunger: Double = 0.0    // neko.swift:153
    var energy: Double = 0.7    // neko.swift:154
    var boredom: Double = 0.3   // neko.swift:155
}

// States that produce drive drift. .other covers digging/away/falling (default: no drift).
enum DriveState { case sleep, walk, zoomies, idle, other }

// Only .hungry changes hunger growth; everything else behaves like .normal here.
enum DriveMood { case hungry, normal }

// neko.swift:453 — hunger growth per tick (hungry mood grows ~2x), clamped to <=1.
func growHunger(_ hunger: Double, mood: DriveMood) -> Double {
    return min(1, hunger + (mood == .hungry ? HUNGER_STEP_HUNGRY : HUNGER_STEP_NORMAL))
}

// neko.swift:456-461 — energy/boredom drift by state, clamped to [0,1].
func driftEnergyBoredom(_ d: Drives, state: DriveState) -> Drives {
    var r = d
    switch state {
    case .sleep:          r.energy = min(1, r.energy + 0.0008); r.boredom = min(1, r.boredom + 0.0004)
    case .walk, .zoomies: r.energy = max(0, r.energy - 0.0016); r.boredom = max(0, r.boredom - 0.0025)
    case .idle:           r.energy = min(1, r.energy + 0.0003); r.boredom = min(1, r.boredom + 0.0007)
    case .other:          break
    }
    return r
}

// Combined per-tick drive update (order in tick(): hunger first, then energy/boredom).
func tickDrives(_ d: Drives, state: DriveState, mood: DriveMood) -> Drives {
    var r = d
    r.hunger = growHunger(r.hunger, mood: mood)   // line 453
    r = driftEnergyBoredom(r, state: state)       // lines 456-461
    return r
}

// neko.swift:527 — satiation from one bite, clamped to >=0.
func satiateBite(_ hunger: Double, maxBites: Int) -> Double {
    return max(0, hunger - SATIATION / Double(maxBites))
}

// neko.swift:717-719 — restore clamps each drive into [0,1].
func clampRestore(_ v: Double) -> Double {
    return min(1, max(0, v))
}

// =====================================================================
// MARK: 2) ACTION SELECTION — decideNext()
// =====================================================================

enum CatState: Equatable { case sleep, walk, zoomies, idle }
enum Mood: Equatable { case playful, lazy, curious, hungry, normal }

struct Needs {            // all 0...1
    var hunger: Double
    var energy: Double
    var boredom: Double
}

struct Decision: Equatable {
    var state: CatState
    var toFood: Bool = false     // walking toward kibble pile (food override)
    var goingAway: Bool = false  // wandering off the edge
    var awayLeft: Bool = false   // which edge (only meaningful when goingAway)
}

// hasFood == (pileCenter() != nil), i.e. kibbles non-empty.
// Mirrors decideNext(), neko.swift:374-425.
func chooseAction<R: RandomSource>(
    needs: Needs, hour: Int, mood: Mood, hasFood: Bool, rng: inout R
) -> Decision {
    // food override — neko.swift:376-378 (early return, no RNG, no weight math)
    if needs.hunger > EAT_HUNGER && hasFood {
        return Decision(state: .walk, toFood: true)
    }

    let hN = needs.hunger                                 // neko.swift:380
    let night = hour >= 23 || hour < 6                    // neko.swift:382
    let crep = (hour >= 6 && hour < 9) || (hour >= 18 && hour < 22)  // neko.swift:383

    var wSleep = (1.4 - needs.energy) + (night ? 1.4 : 0.3)              // :386
    var wWalk  = 0.5 + needs.boredom * 0.9 + needs.energy * 0.3         // :387
    var wZoom  = max(0, needs.boredom * needs.energy * (0.4 + hN)) * (crep ? 2.0 : 0.5) // :388
    var wIdle  = 0.5                                                     // :389

    switch mood {                                          // neko.swift:392-398
    case .playful: wZoom *= 2.2; wWalk *= 1.4; wSleep *= 0.7
    case .lazy:    wSleep *= 1.7; wWalk *= 0.6; wZoom *= 0.4
    case .curious: wWalk *= 1.8; wIdle *= 0.7
    case .hungry:  wZoom *= 1.5; wWalk *= 1.2
    case .normal:  break
    }

    let weights: [(CatState, Double)] =
        [(.sleep, wSleep), (.walk, wWalk), (.zoomies, wZoom), (.idle, wIdle)]
    let total = weights.reduce(0) { $0 + max(0, $1.1) }    // neko.swift:401
    var pick = CatState.idle                               // neko.swift:402
    if total > 0 {                                         // neko.swift:403
        var r = rng.uniform(in: 0..<total)                // neko.swift:404
        for (s, w) in weights { if r < max(0, w) { pick = s; break }; r -= max(0, w) } // :405
    }

    let awayChance = (mood == .curious) ? 0.16 : 0.07     // neko.swift:408
    switch pick {                                          // neko.swift:409-424
    case .zoomies:
        return Decision(state: .zoomies)
    case .walk:
        if rng.uniform(in: 0..<1) < awayChance {
            return Decision(state: .walk, goingAway: true, awayLeft: rng.nextBool())
        } else {
            return Decision(state: .walk)                 // targetX = randomX() in app
        }
    case .sleep:
        return Decision(state: .sleep)
    default:
        return Decision(state: .idle)
    }
}

// =====================================================================
// MARK: 3) FOOD TARGETING & EATING
// =====================================================================

struct Kibble: Equatable {
    var x: Double            // center X
    var y: Double = 0        // window-origin Y (bottom)
    var vx: Double = 0
    var vy: Double = 0
    var landed: Bool = false
    var dragging: Bool = false
    var canEscape: Bool = false
    var eaten: Int = 0
    var maxBites: Int = 4
}

// neko.swift:369-372 — average X of ALL kibbles (landed or not, dragging or not).
func pileCenter(_ ks: [Kibble]) -> Double? {
    if ks.isEmpty { return nil }
    return ks.map { $0.x }.reduce(0, +) / Double(ks.count)
}

// EAT_HUNGER gate used in decideNext (neko.swift:376): strict >. Returns target X or nil.
func decideFoodTarget(hunger: Double, kibbles: [Kibble]) -> Double? {
    guard hunger > EAT_HUNGER, let c = pileCenter(kibbles) else { return nil }
    return c
}

// tick attractor (neko.swift:463-472): redirect toward food mid-behavior.
enum AttractAction: Equatable { case none, retargetWalk(Double), startWalk(Double) }
func foodAttractor(state: String, hunger: Double, eating: Bool,
                   goingAway: Bool, leaving: Bool, kibbles: [Kibble]) -> AttractAction {
    guard hunger > EAT_HUNGER, !eating, !goingAway, !leaving,
          let c = pileCenter(kibbles) else { return .none }
    switch state {
    case "walk":            return .retargetWalk(c)   // only fix target, keep anim
    case "zoomies", "idle": return .startWalk(c)      // enter(.walk)
    default:                return .none              // sleep/away/digging/falling untouched
    }
}

// eat range test, neko.swift:521 & 847: inclusive <= SIZE/2 (== 32).
func inEatRange(kibbleX: Double, catX: Double) -> Bool {
    abs(kibbleX - catX) <= SIZE / 2
}

// eatNearbyKibble, neko.swift:845-853: top-most (max y) landed kibble in range.
func eatNearbyKibbleIndex(catX: Double, kibbles: [Kibble]) -> Int? {
    let cand = kibbles.indices.filter { kibbles[$0].landed && inEatRange(kibbleX: kibbles[$0].x, catX: catX) }
    return cand.max(by: { kibbles[$0].y < kibbles[$1].y })
}

// chewed-sprite stage, neko.swift:528-529.
func biteStage(eaten: Int, maxBites: Int) -> Int {
    min(STAGES_COUNT - 1, Int(Double(eaten) / Double(maxBites) * Double(STAGES_COUNT)))
}

// one applied bite (body of `if biteTick >= 16`), neko.swift:524-535.
struct BiteResult: Equatable { var hunger: Double; var kibble: Kibble; var stage: Int; var finished: Bool }
func applyBite(hunger: Double, kibble: Kibble) -> BiteResult {
    var k = kibble
    k.eaten += 1
    let h = max(0, hunger - SATIATION / Double(k.maxBites))
    let stage = biteStage(eaten: k.eaten, maxBites: k.maxBites)
    return BiteResult(hunger: h, kibble: k, stage: stage, finished: k.eaten >= k.maxBites)
}

// idle-eating guard, neko.swift:521: keep eating only if still valid.
func canKeepEating(_ k: Kibble, catX: Double) -> Bool {
    k.landed && !k.dragging && inEatRange(kibbleX: k.x, catX: catX)
}

// =====================================================================
// MARK: 4) KIBBLE PHYSICS — updateKibbles()
// =====================================================================

struct World { var minX: Double; var maxX: Double; var minY: Double; var maxY: Double }
let G: Double = 2.2          // neko.swift:790
let HALF: Double = 7         // 14pt dot half-width used in wall clamps, neko.swift:810-812
let STACK: Double = 8        // vertical offset between stacked kibbles, neko.swift:794 etc.

// Mirrors makeKibble.onEnded (neko.swift:776-781): thrown from upper half -> may fly off.
func releaseKibble(_ k: inout Kibble, world: World) {
    k.dragging = false
    k.landed = false
    k.canEscape = k.y > (world.minY + world.maxY) / 2   // == frame.midY
}

// One physics tick over the whole array (neko.swift:787-842). Returns survivors
// (escaped ones dropped), preserving original order. randBool drives the exact-tie
// slide direction (Bool.random(), neko.swift:831).
func stepKibbles(_ input: [Kibble], world: World, randBool: () -> Bool = { Bool.random() }) -> [Kibble] {
    var ks = input
    let base = world.minY

    // 1) stability pre-pass (neko.swift:793-798): elevated landed kibble needs
    //    support on BOTH sides else it unlands.
    for i in ks.indices where ks[i].landed && !ks[i].dragging && ks[i].y > base + 1 {
        let k = ks[i]
        let below = ks.enumerated().filter { (j, o) in
            j != i && o.landed && !o.dragging && abs(o.x - k.x) < 11 && abs(o.y + STACK - k.y) < 5
        }.map { $0.element }
        let hasLeft  = below.contains { $0.x < k.x - 2 }
        let hasRight = below.contains { $0.x > k.x + 2 }
        if !(hasLeft && hasRight) { ks[i].landed = false }
    }

    // 2) integrate + collide every loose kibble; collect escapes (neko.swift:799-841).
    var remove = Set<Int>()
    for i in ks.indices where !ks[i].landed && !ks[i].dragging {
        ks[i].vy -= G                  // :801
        ks[i].vx *= 0.99               // :802
        ks[i].x  += ks[i].vx           // :803
        ks[i].y  += ks[i].vy           // :804
        if ks[i].canEscape {           // :805-808
            if ks[i].x < world.minX - 40 || ks[i].x > world.maxX + 40 || ks[i].y > world.maxY + 150 {
                remove.insert(i); continue
            }
        } else {                       // :809-813
            if ks[i].x < world.minX + HALF { ks[i].x = world.minX + HALF; ks[i].vx =  abs(ks[i].vx) * 0.5 }
            if ks[i].x > world.maxX - HALF { ks[i].x = world.maxX - HALF; ks[i].vx = -abs(ks[i].vx) * 0.5 }
            if ks[i].y > world.maxY - HALF { ks[i].y = world.maxY - HALF; ks[i].vy = -abs(ks[i].vy) * 0.4 }
        }
        let k = ks[i]
        let near = ks.enumerated().filter { (j, o) in
            j != i && o.landed && !o.dragging && abs(o.x - k.x) < 11
        }.map { $0.element }                                  // :814
        let supK = near.max(by: { $0.y < $1.y })            // :815
        let supTop = max(base, supK.map { $0.y + STACK } ?? base)  // :816
        if ks[i].y <= supTop && ks[i].vy <= 0 {             // :817
            if -ks[i].vy > 3 {                              // :818-819 hard impact -> bounce
                ks[i].y = supTop; ks[i].vy = -ks[i].vy * 0.32; ks[i].vx *= 0.6
            } else if supTop == base {                      // :820-823 settle on floor
                ks[i].y = base; ks[i].vy = 0
                ks[i].x = min(max(ks[i].x, world.minX + HALF), world.maxX - HALF)
                if abs(ks[i].vx) < 0.4 { ks[i].vx = 0; ks[i].landed = true }
            } else if let sup = supK {                      // :824-836 resting on a kibble
                let hasLeft  = near.contains { $0.x < k.x - 2 && abs($0.y + STACK - supTop) < 4 }
                let hasRight = near.contains { $0.x > k.x + 2 && abs($0.y + STACK - supTop) < 4 }
                if hasLeft && hasRight {                     // wedged in a pit -> land
                    ks[i].y = supTop; ks[i].vx = 0; ks[i].vy = 0; ks[i].landed = true
                } else {                                     // single support -> slide off sideways
                    var dir: Double = k.x >= sup.x ? 1 : -1
                    if abs(k.x - sup.x) < 0.5 { dir = randBool() ? 1 : -1 }
                    ks[i].x += dir * 2.2
                    ks[i].y = supTop - 2
                    ks[i].vy = 0
                }
            }
        }
        if ks[i].y <= base + 2 { ks[i].vx *= 0.85 }         // :838 ground friction
    }
    return ks.enumerated().filter { !remove.contains($0.offset) }.map { $0.element }
}
