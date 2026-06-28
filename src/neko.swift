import Cocoa
import Carbon.HIToolbox

// Спокойный oneko: живёт на нижней кромке, много спит, изредка мягко гуляет.
// Корм по ⌃⌥⌘X — у курсора насыпается горка; кот придёт есть, когда сам проснётся.
// Кота можно перетащить мышью.
let CELL = 32
let SCALE: CGFloat = 2
let SIZE = CGFloat(CELL) * SCALE      // 64
let SPEED: CGFloat = 4                // мягкая походка
let TICK = 0.1

final class NekoWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Кот: ловит перетаскивание
final class NekoView: NSImageView {
    var began: (() -> Void)?
    var moved: ((CGPoint) -> Void)?
    var ended: (() -> Void)?
    private var startMouse = NSPoint.zero
    private var startOrigin = NSPoint.zero
    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        began?()
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        // курсор держит кота за фиксированную точку (за «попу» сверху), тело свисает
        let o = NSPoint(x: m.x - bounds.width / 2, y: m.y - bounds.height * 0.85)
        window?.setFrameOrigin(o)
        let angle = max(-30, min(30, -Double(e.deltaX) * 1.4))   // маятник
        frameCenterRotation = angle
        moved?(o)
    }
    override func mouseUp(with e: NSEvent) {
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.25
            animator().frameCenterRotation = 0
        }
        ended?()
    }
}

// Катышек корма — пиксель-арт, 4 стадии «надкусанности»
final class KibbleDot: NSView {
    static let stages: [[String]] = [
        [ "..###..", ".#WWW#.", "#WWWWW#", "#WWWWW#", "#WWWWW#", ".#WWW#.", "..###.." ], // целый
        [ ".......", "..#.#..", "#WWWWW#", "#WWWWW#", "#WWWWW#", ".#WWW#.", "..###.." ], // верх надкушен
        [ ".......", ".......", ".......", "#W#.#W#", "#WWWWW#", ".#WWW#.", "..###.." ], // половина сверху
        [ ".......", ".......", ".......", ".......", ".......", "..#.#..", "..###.." ], // крошка снизу
    ]
    var stage = 0 { didSet { needsDisplay = true } }
    var onBegan: (() -> Void)?
    var onMoved: ((CGPoint) -> Void)?
    var onEnded: (() -> Void)?
    private var startMouse = NSPoint.zero, startOrigin = NSPoint.zero
    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation
        startOrigin = window?.frame.origin ?? .zero
        onBegan?()
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        let o = NSPoint(x: startOrigin.x + (m.x - startMouse.x), y: startOrigin.y + (m.y - startMouse.y))
        window?.setFrameOrigin(o); onMoved?(o)
    }
    override func mouseUp(with e: NSEvent) { onEnded?() }

    override func draw(_ r: NSRect) {
        let rows = KibbleDot.stages[min(stage, KibbleDot.stages.count - 1)]
        let h = rows.count, w = 7
        let cell = floor(min(bounds.width / CGFloat(w), bounds.height / CGFloat(h)))
        let ox = (bounds.width - cell * CGFloat(w)) / 2
        let oy = (bounds.height - cell * CGFloat(h)) / 2
        for (ri, row) in rows.enumerated() {
            for (ci, ch) in row.enumerated() {
                let color: NSColor? = ch == "#" ? .black : (ch == "W" ? .white : nil)
                guard let c = color else { continue }
                c.setFill()
                NSRect(x: ox + CGFloat(ci) * cell, y: oy + CGFloat(h - 1 - ri) * cell,
                       width: cell, height: cell).fill()
            }
        }
    }
}

final class Kibble {
    let win: NSWindow
    let dot: KibbleDot
    var x: CGFloat          // центр по X
    var y: CGFloat          // origin окна по Y
    var vx: CGFloat = 0     // скорость (инерция)
    var vy: CGFloat = 0
    var landed = false
    var dragging = false    // тащат мышью
    var canEscape = false   // можно ли вылететь за экран (бросок из верхней половины)
    var eaten = 0           // сколько откусано
    let maxBites: Int       // за сколько укусов исчезнет
    init(win: NSWindow, dot: KibbleDot, x: CGFloat, y: CGFloat, maxBites: Int) {
        self.win = win; self.dot = dot; self.x = x; self.y = y; self.maxBites = maxBites
    }
}

enum St { case sleep, idle, walk, digging, away, falling, zoomies }

final class AppDelegate: NSObject, NSApplicationDelegate {
    var win: NSWindow!
    let iv = NekoView()
    var sheet: NSImage!
    var cache: [String: NSImage] = [:]
    var x: CGFloat = 400, y: CGFloat = 400
    var anim = 0
    var st: St = .idle
    var stTicks = 0, stDur = 40
    var targetX: CGFloat?
    var eating = false
    var dragging = false
    var kibbles: [Kibble] = []
    let FALL: CGFloat = 22          // скорость падения корма
    let FOOT: CGFloat = 8           // насколько опустить кота к самой кромке
    var goingAway = false
    var leaving = false
    var awayLeft = false
    var fallVy: CGFloat = 0     // вертикальная скорость при падении
    var fallY: CGFloat = 0
    var hunger = 0             // тиков без еды
    var energy = 0.7           // 0..1 — растёт во сне, тратится в активности
    var boredom = 0.3          // 0..1 — растёт в покое, падает от движения
    var zoomReps = 0           // сколько ещё рывков «носиться»
    var toFood = false         // спешит к корму
    var eatingRef: Kibble?     // что грызёт сейчас
    var biteTick = 0           // тики до следующего укуса
    let ZOOM: CGFloat = 13     // скорость беготни
    let FOOD_SPEED: CGFloat = 9 // скорость к корму
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var pourTimer: Timer?

    let sets: [String: [(Int, Int)]] = [
        "idle":    [(3, 3)],
        "alert":   [(7, 3)],
        "scratch": [(5, 0), (6, 0), (7, 0)],
        "sleep":   [(2, 0), (2, 1)],
        "held":    [(3, 1), (5, 2)],            // болтается ногами при переносе
        "fall":    [(1, 2), (1, 3)],            // барахтается лапками в падении
        "eat":     [(7, 2)],                    // ест сверху (голова вниз)
        "digL":    [(4, 0), (4, 1)],            // копает стену слева
        "digR":    [(2, 2), (2, 3)],            // копает стену справа
        "E":  [(3, 0), (3, 1)], "W": [(4, 2), (4, 3)],
    ]

    func applicationDidFinishLaunching(_ n: Notification) {
        NSApp.setActivationPolicy(.accessory)
        guard let url = Bundle.main.url(forResource: "oneko", withExtension: "png"),
              let img = NSImage(contentsOf: url) else {
            FileHandle.standardError.write(Data("oneko.png не найден\n".utf8)); NSApp.terminate(nil); return
        }
        sheet = img

        win = NekoWindow(contentRect: NSRect(x: 0, y: 0, width: SIZE, height: SIZE),
                         styleMask: .borderless, backing: .buffered, defer: false)
        win.isOpaque = false; win.backgroundColor = .clear; win.hasShadow = false
        win.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 1)
        win.ignoresMouseEvents = false   // чтобы можно было схватить кота
        win.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
        iv.frame = NSRect(x: 0, y: 0, width: SIZE, height: SIZE)
        iv.imageScaling = .scaleNone
        iv.began = { [weak self] in self?.dragBegan() }
        iv.moved = { [weak self] o in self?.x = o.x + SIZE / 2 }
        iv.ended = { [weak self] in self?.dragEnded() }
        win.contentView = iv
        x = NSScreen.main?.frame.midX ?? 400
        y = bottomY()
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
        win.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeCatIcon()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Насыпать корм (⌃⌥⌘X)", action: #selector(feedMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Погулять (уйти за стену)", action: #selector(walkMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Выход", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        statusItem.menu = menu

        registerFoodHotkey()
        enter(.sleep)
        Timer.scheduledTimer(withTimeInterval: TICK, repeats: true) { [weak self] _ in self?.tick() }

        if CommandLine.arguments.contains("--demo-walk") {   // разовый показ ухода
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startWalkabout() }
        }
    }

    // Значок менюбара — голова кота, вырезанная из кадра (3,3) спрайта
    func makeCatIcon() -> NSImage {
        let src = NSRect(x: 99, y: 14, width: 24, height: 17)   // область головы в oneko.png
        let h: CGFloat = 19, w = h * (src.width / src.height)
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        sheet.draw(in: NSRect(x: 0, y: 0, width: w, height: h), from: src, operation: .sourceOver, fraction: 1)
        img.unlockFocus()
        return img
    }

    func bottomY() -> CGFloat { (NSScreen.main ?? NSScreen.screens[0]).frame.minY + SIZE / 2 - FOOT }
    func leftEdge() -> CGFloat  { (NSScreen.main ?? NSScreen.screens[0]).frame.minX + SIZE / 2 }
    func rightEdge() -> CGFloat { (NSScreen.main ?? NSScreen.screens[0]).frame.maxX - SIZE / 2 }
    func randomX() -> CGFloat {
        let s = NSScreen.main ?? NSScreen.screens[0]
        return CGFloat.random(in: (s.frame.minX + SIZE)...(s.frame.maxX - SIZE))
    }

    func frame(_ set: String, _ idx: Int) -> NSImage {
        let arr = sets[set] ?? sets["idle"]!
        let (c, r) = arr[idx % arr.count]
        let key = "\(c),\(r)"
        if let cached = cache[key] { return cached }
        let sh = sheet.size.height
        let src = NSRect(x: CGFloat(c) * 32, y: sh - CGFloat(r + 1) * 32, width: 32, height: 32)
        let out = NSImage(size: NSSize(width: SIZE, height: SIZE))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        sheet.draw(in: NSRect(x: 0, y: 0, width: SIZE, height: SIZE), from: src, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        cache[key] = out
        return out
    }

    // MARK: перетаскивание
    func dragBegan() { dragging = true; iv.image = frame("held", 0) }
    func dragEnded() {
        dragging = false
        x = win.frame.origin.x + SIZE / 2
        fallY = win.frame.origin.y + SIZE / 2   // откуда падать
        fallVy = 0
        st = .falling                           // мягко приземлится на лапы
    }

    // MARK: состояние
    func enter(_ s: St) {
        st = s; stTicks = 0
        switch s {
        case .sleep:   stDur = Int.random(in: 600...1600)
        case .idle:    stDur = Int.random(in: 40...110)
        case .walk:    stDur = 0
        case .digging: stDur = Int.random(in: 30...50)      // ~3–5 c копает
        case .away:    stDur = Int.random(in: 1800...6000)  // 3–10 мин гуляет
        case .falling: stDur = 0
        case .zoomies: stDur = 0; zoomReps = Int.random(in: 5...10)
                       targetX = Bool.random() ? leftEdge() : rightEdge()
        }
    }

    // что делать, когда сам проснулся / закончил сидеть
    func pileCenter() -> CGFloat? {
        let xs = kibbles.map { $0.x }
        return xs.isEmpty ? nil : xs.reduce(0, +) / CGFloat(xs.count)
    }

    func decideNext() {
        toFood = false
        if let c = pileCenter() { toFood = true; targetX = c; enter(.walk); return }  // корм важнее всего

        let hN = min(1.0, Double(hunger) / 9000.0)          // 0..1 — насколько голоден (15 мин = совсем)
        let hour = Calendar.current.component(.hour, from: Date())
        let night = hour >= 23 || hour < 6                  // ночью спит крепче
        let crep = (hour >= 6 && hour < 9) || (hour >= 18 && hour < 22)  // сумерки — пик активности

        // веса действий по потребностям и времени суток
        let weights: [(St, Double)] = [
            (.sleep,   (1.4 - energy) + (night ? 1.4 : 0.3)),                       // устал/ночь → спать
            (.walk,    0.5 + boredom * 0.9 + energy * 0.3),                         // скучно/бодр → бродить
            (.zoomies, max(0, boredom * energy * (0.4 + hN)) * (crep ? 2.0 : 0.5)), // скука+энергия+голод+сумерки → носиться
            (.idle,    0.5),                                                        // посидеть/умыться
        ]
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = Double.random(in: 0..<total)
        var pick = St.idle
        for (s, w) in weights { if r < w { pick = s; break }; r -= w }

        switch pick {
        case .zoomies:
            enter(.zoomies)
        case .walk:
            if Double.random(in: 0..<1) < 0.07 {            // изредка своенравно уходит за стену
                goingAway = true; awayLeft = Bool.random()
                targetX = awayLeft ? leftEdge() : rightEdge()
                enter(.walk)
            } else {
                targetX = randomX(); enter(.walk)
            }
        case .sleep:
            enter(.sleep)
        default:
            enter(.idle)
        }
    }

    func tick() {
        updateKibbles()                     // корм падает всегда
        if dragging {                       // пока несут — болтает ногами
            iv.image = frame("held", anim / 3)
            anim += 1
            return
        }

        if st == .falling {                 // мягко падает на лапы после отпускания
            let ground = bottomY()
            fallVy += 3
            fallY -= fallVy
            if fallY <= ground {
                fallY = ground
                enter(.idle)
                iv.image = frame("idle", 0)
            } else {
                iv.image = frame("fall", anim / 2)   // дрыгает лапками
            }
            win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: fallY - SIZE / 2))
            anim += 1
            return
        }

        y = bottomY()
        stTicks += 1
        hunger += 1

        // потребности: энергия и скука дрейфуют по состоянию
        switch st {
        case .sleep:           energy = min(1, energy + 0.0008); boredom = min(1, boredom + 0.0004)
        case .walk, .zoomies:  energy = max(0, energy - 0.0016); boredom = max(0, boredom - 0.0025)
        case .idle:            energy = min(1, energy + 0.0003); boredom = min(1, boredom + 0.0007)
        default: break
        }

        // корм всегда привлекает — прерывает беготню/ходьбу/сидение (но не сон/уход)
        if !kibbles.isEmpty && !eating && !goingAway && !leaving, let c = pileCenter() {
            switch st {
            case .zoomies, .walk, .idle:
                if st != .walk || abs((targetX ?? x) - c) > 6 {
                    goingAway = false; toFood = true; targetX = c; enter(.walk)
                }
            default: break
            }
        }

        var img: NSImage
        switch st {
        case .zoomies:
            let tx = targetX ?? x
            let dx = tx - x
            if abs(dx) <= ZOOM {
                x = tx
                zoomReps -= 1
                if zoomReps <= 0 { enter(.idle); img = frame("idle", 0) }
                else { targetX = (tx <= leftEdge() + 1) ? rightEdge() : leftEdge()
                       img = frame(dx > 0 ? "E" : "W", Int(abs(x) / 7)) }
            } else {
                x += dx > 0 ? ZOOM : -ZOOM
                img = frame(dx > 0 ? "E" : "W", Int(abs(x) / 7))   // кадр лап от пути
            }
        case .walk:
            let sp: CGFloat = toFood ? FOOD_SPEED : SPEED
            let tx = targetX ?? x
            let dx = tx - x
            if abs(dx) <= sp {
                x = tx
                if leaving { leaving = false; win.orderOut(nil); enter(.away); img = frame("idle", 0) }
                else if goingAway { enter(.digging); img = frame(awayLeft ? "digL" : "digR", 0) }
                else { toFood = false; eatNearbyKibble(); enter(.idle); img = frame("idle", 0) }
            } else {
                x += dx > 0 ? sp : -sp
                img = frame(dx > 0 ? "E" : "W", Int(abs(x) / 9))   // кадр лап от пройденного пути
            }
        case .digging:
            img = frame(awayLeft ? "digL" : "digR", stTicks / 5)   // копает дырку
            if stTicks > stDur {                    // прокопал → уходит за край шагами
                leaving = true; goingAway = false
                targetX = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                enter(.walk)
            }
        case .away:
            img = frame("idle", 0)                  // не виден
            if stTicks > stDur {                    // возвращается из-за края шагами
                goingAway = false; leaving = false
                x = awayLeft ? leftEdge() - SIZE : rightEdge() + SIZE
                y = bottomY()
                win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
                win.orderFrontRegardless()
                targetX = randomX(); toFood = false; enter(.walk)
            }
        case .idle:
            if eating {
                if let k = eatingRef, k.landed, !k.dragging {   // ест только лежащий, не схваченный
                    img = frame("eat", 0)
                    biteTick += 1
                    if biteTick >= 16 {             // очередной укус
                        biteTick = 0
                        k.eaten += 1
                        k.dot.stage = min(KibbleDot.stages.count - 1,
                                          Int(Double(k.eaten) / Double(k.maxBites) * Double(KibbleDot.stages.count)))
                        if k.eaten >= k.maxBites {  // доел этот катышек
                            k.win.orderOut(nil)
                            kibbles.removeAll { $0 === k }
                            eatingRef = nil; eating = false; hunger = 0
                            decideNext()
                        }
                    }
                } else {                            // схватили/улетел — перестаём есть
                    eating = false; eatingRef = nil; img = frame("idle", 0)
                }
            } else {
                if stTicks > stDur / 4 && stTicks < stDur * 3 / 4 {
                    img = frame("scratch", stTicks / 4)     // умывается
                } else {
                    img = frame("idle", 0)
                }
                if stTicks > stDur { decideNext() }
            }
        case .sleep:
            img = frame("sleep", stTicks / 8)
            if stTicks > stDur { decideNext() }             // ест только когда сам проснулся
        case .falling:
            img = frame("held", 0)                          // (обрабатывается выше)
        }
        iv.image = img
        let drop: CGFloat = eating ? 6 : 0   // когда ест — садится ниже, чтоб попа не висела
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2 - drop))
        anim += 1
    }

    @objc func walkMenu() { startWalkabout() }

    func startWalkabout() {        // уйти гулять за стену (вызывается сам / для демо)
        goingAway = true; toFood = false; awayLeft = Bool.random()
        targetX = awayLeft ? leftEdge() : rightEdge()
        enter(.walk)
    }

    // MARK: корм
    @objc func feedMenu() { dropKibble() }

    // высыпать один катышек из позиции курсора (падает на пол)
    func dropKibble() {
        if kibbles.count >= 80 { return }   // лимит, чтобы не наплодить окон
        let s = NSScreen.main ?? NSScreen.screens[0]
        let m = NSEvent.mouseLocation
        let sz: CGFloat = 14
        let cx = min(max(m.x, s.frame.minX + 8), s.frame.maxX - 8)
        let w = NekoWindow(contentRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                           styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2) // спереди кота
        w.ignoresMouseEvents = false   // можно перекладывать
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let dot = KibbleDot(frame: NSRect(x: 0, y: 0, width: sz, height: sz))
        w.contentView = dot
        let startY = m.y - sz / 2
        w.setFrameOrigin(NSPoint(x: cx - sz / 2, y: startY))
        w.orderFrontRegardless()
        let kib = Kibble(win: w, dot: dot, x: cx, y: startY, maxBites: Int.random(in: 3...4))
        dot.onBegan = { [weak kib] in kib?.dragging = true; kib?.landed = false; kib?.vx = 0; kib?.vy = 0 }
        dot.onMoved = { [weak kib] o in
            guard let kib = kib else { return }
            let nx = o.x + sz / 2
            kib.vx = max(-45, min(45, nx - kib.x))     // инерция от движения руки
            kib.vy = max(-45, min(45, o.y - kib.y))
            kib.x = nx; kib.y = o.y
        }
        dot.onEnded = { [weak self, weak kib] in
            guard let kib = kib else { return }
            kib.dragging = false; kib.landed = false
            let mid = (NSScreen.main ?? NSScreen.screens[0]).frame.midY
            kib.canEscape = kib.y > mid     // из верхней половины — улетит; из нижней — отскочит
            _ = self
        }
        kibbles.append(kib)
    }

    // гравитация: падают до пола
    func updateKibbles() {
        let s = NSScreen.main ?? NSScreen.screens[0]
        let base = s.frame.minY
        let G: CGFloat = 2.2
        // устойчивость: приподнятый катышек держится только если подпёрт С ОБЕИХ сторон (ямка),
        // иначе осыпается — в т.ч. прямо когда вытаскиваешь нижний
        for k in kibbles where k.landed && !k.dragging && k.y > base + 1 {
            let below = kibbles.filter { $0 !== k && $0.landed && !$0.dragging && abs($0.x - k.x) < 11 && abs($0.y + 8 - k.y) < 5 }
            let hasLeft  = below.contains { $0.x < k.x - 2 }
            let hasRight = below.contains { $0.x > k.x + 2 }
            if !(hasLeft && hasRight) { k.landed = false }
        }
        var remove: [Kibble] = []
        for k in kibbles where !k.landed && !k.dragging {
            k.vy -= G                     // гравитация
            k.vx *= 0.99                  // воздух
            k.x += k.vx
            k.y += k.vy
            if k.canEscape {                              // бросок из верхней половины — может улететь
                if k.x < s.frame.minX - 40 || k.x > s.frame.maxX + 40 || k.y > s.frame.maxY + 150 {
                    remove.append(k); continue
                }
            } else {                                      // иначе держим на экране — отскок от стен/потолка
                if k.x < s.frame.minX + 7 { k.x = s.frame.minX + 7; k.vx = abs(k.vx) * 0.5 }
                if k.x > s.frame.maxX - 7 { k.x = s.frame.maxX - 7; k.vx = -abs(k.vx) * 0.5 }
                if k.y > s.frame.maxY - 7 { k.y = s.frame.maxY - 7; k.vy = -abs(k.vy) * 0.4 }
            }
            let near = kibbles.filter { $0 !== k && $0.landed && !$0.dragging && abs($0.x - k.x) < 11 }
            let supK = near.max(by: { $0.y < $1.y })          // на ком лежит (самый высокий рядом)
            let supTop = max(base, (supK.map { $0.y + 8 }) ?? base)
            if k.y <= supTop && k.vy <= 0 {
                if -k.vy > 3 {                                // удар → отскок (невысокий: масса)
                    k.y = supTop; k.vy = -k.vy * 0.32; k.vx *= 0.6
                } else if supTop == base {                    // лёг на пол
                    k.y = base; k.vy = 0
                    k.x = min(max(k.x, s.frame.minX + 7), s.frame.maxX - 7)
                    if abs(k.vx) < 0.4 { k.vx = 0; k.landed = true }
                } else if let sup = supK {                    // лёг на катышек
                    let hasLeft  = near.contains { $0.x < k.x - 2 && abs($0.y + 8 - supTop) < 4 }
                    let hasRight = near.contains { $0.x > k.x + 2 && abs($0.y + 8 - supTop) < 4 }
                    if hasLeft && hasRight {                  // в ямке между двумя → лёг
                        k.y = supTop; k.vx = 0; k.vy = 0; k.landed = true
                    } else {                                  // на одной опоре → монотонно съезжает вбок и падает
                        var dir: CGFloat = k.x >= sup.x ? 1 : -1
                        if abs(k.x - sup.x) < 0.5 { dir = Bool.random() ? 1 : -1 }
                        k.x += dir * 2.2
                        k.y = supTop - 2
                        k.vy = 0
                    }
                }
            }
            if k.y <= base + 2 { k.vx *= 0.85 }           // трение по земле
            k.win.setFrameOrigin(NSPoint(x: k.x - 7, y: k.y))
        }
        for k in remove { k.win.orderOut(nil); kibbles.removeAll { $0 === k } }
    }

    // съесть катышек рядом с котом (в точке остановки)
    func eatNearbyKibble() {
        // начинает грызть верхний катышек кучки (с максимальным y)
        let inRange = kibbles.filter { $0.landed && abs($0.x - x) <= SIZE / 2 }
        if let top = inRange.max(by: { $0.y < $1.y }) {
            eatingRef = top
            biteTick = 0
            eating = true
        }
    }

    // MARK: хоткей ⌃⌥⌘X
    func startPour() {
        dropKibble()
        pourTimer?.invalidate()
        pourTimer = Timer.scheduledTimer(withTimeInterval: 0.4, repeats: true) { [weak self] _ in self?.dropKibble() }
    }
    func stopPour() { pourTimer?.invalidate(); pourTimer = nil }

    func registerFoodHotkey() {
        var specs = [
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
            EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased)),
        ]
        InstallEventHandler(GetApplicationEventTarget(), { (_, event, userData) -> OSStatus in
            let me = Unmanaged<AppDelegate>.fromOpaque(userData!).takeUnretainedValue()
            let kind = GetEventKind(event)
            DispatchQueue.main.async {
                if kind == UInt32(kEventHotKeyPressed) { me.startPour() } else { me.stopPour() }
            }
            return noErr
        }, 2, &specs, Unmanaged.passUnretained(self).toOpaque(), nil)
        let id = EventHotKeyID(signature: OSType(0x4e_45_4b_4f), id: 1)
        let mods = UInt32(cmdKey | optionKey | controlKey)
        RegisterEventHotKey(UInt32(kVK_ANSI_X), mods, id, GetApplicationEventTarget(), 0, &hotKeyRef)
    }
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.run()
