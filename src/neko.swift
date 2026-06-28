import Cocoa
import Carbon.HIToolbox

// Спокойный oneko: живёт на нижней кромке, много спит, изредка мягко гуляет.
// Корм по ⌃⌥⌘X — у курсора насыпается горка; кот придёт есть, когда сам проснётся.
// Кота можно перетащить мышью.
let VERSION = "1.0.12"
let REPO = "superbereza/neko"
let CELL = 32
let SCALE: CGFloat = 2
let SIZE = CGFloat(CELL) * SCALE      // 64
let SPEED: CGFloat = 2.5              // спокойная ходьба (бег — только в zoomies)
let TICK = 0.1

func rgb(_ r: Int, _ g: Int, _ b: Int) -> NSColor {
    NSColor(srgbRed: CGFloat(r) / 255, green: CGFloat(g) / 255, blue: CGFloat(b) / 255, alpha: 1)
}

final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
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
    let FOOT: CGFloat = 8           // насколько опустить кота к самой кромке
    var goingAway = false
    var leaving = false
    var awayLeft = false
    var fallVy: CGFloat = 0     // вертикальная скорость при падении
    var fallVx: CGFloat = 0     // горизонтальная скорость (бросок по параболе)
    var fallY: CGFloat = 0
    var hunger = 0.0          // 0..1 — растёт со временем, обнуляется едой (~15 мин до макс.)
    var energy = 0.7           // 0..1 — растёт во сне, тратится в активности
    var boredom = 0.3          // 0..1 — растёт в покое, падает от движения
    var zoomReps = 0           // сколько ещё рывков «носиться»
    var zoomHop = 0            // тики текущего подскока на бегу (0 = не прыгает)
    var huntHopH: CGFloat = 60     // высота прыжка-охоты (к курсору над котом)
    var huntStartX: CGFloat = 0    // откуда прыгнул
    var huntAimX: CGFloat = 0      // куда целится (x курсора в момент прыжка)
    var huntCool = 0               // кулдаун между прыжками
    var hoverTicks = 0             // сколько мышь висит над котом (нужно «зависание», не пролёт)
    var clinging = false           // висит на курсоре
    var clingPrevX: CGFloat = 0    // прошлый x курсора (для раскачки)
    var clingAngle: CGFloat = 0    // угол маятника
    var clingVel: CGFloat = 0      // угловая скорость маятника
    var flySpin: CGFloat = 0       // закрутка в полёте (после срыва с раскачки)
    var flyRot: CGFloat = 0        // накопленный угол вращения в полёте
    var flyHang = false            // в полёте поза «висения» (вытянутые лапы), а не барахтанье
    var clingTicks = 0             // сколько висит (чтобы не срывался мгновенно при зацепе)
    var clingPivotV: CGFloat = 0   // скорость пивота-курсора (для ускорения подвеса)
    var hopOffset: CGFloat = 0     // подъём при прыжке (дуга)
    var toFood = false         // спешит к корму
    var yarn: Yarn?            // клубок (одна штука), кот за ним гоняется
    var toPlay = false         // спешит к клубку поиграть
    var playSat = 0.0          // 0..1 — насколько клубок надоел (растёт от игры, спадает со временем)
    var playTired = false      // наигрался — отдыхает, пока интерес не восстановится (гистерезис)
    var playDir: CGFloat = 1   // в какую сторону толкнуть в этот раз (чередуется)
    var eatingRef: Kibble?     // что грызёт сейчас
    var biteTick = 0           // тики до следующего укуса
    let ZOOM: CGFloat = 13     // скорость беготни
    let FOOD_SPEED: CGFloat = 9 // скорость к корму
    let HUNGER_RATE = 0.0000035 // голод до максимума ~8 ч (как у живой кошки); голодное настроение — вдвое быстрее
    let SATIATION = 0.13        // один катышек насыщает немного — сытный приём это ~3–5 катышков
    let EAT_HUNGER = 0.5        // идёт к корму, проголодавшись (~через 4 ч после еды)
    let FULL = 0.05            // ест, пока голод не упадёт почти до нуля
    var statusItem: NSStatusItem!
    var hotKeyRef: EventHotKeyRef?
    var pourTimer: Timer?
    var mood: Mood = .normal     // настроение дня (меняет поведение)
    // дебаг доступен только при спец-запуске: open Neko.app --args --debug  /  NEKO_DEBUG=1
    let debugBuild = CommandLine.arguments.contains("--debug")
        || ProcessInfo.processInfo.environment["NEKO_DEBUG"] == "1"
    var debug = UserDefaults.standard.bool(forKey: "neko.debug")  // показывать ли строки (внутри дебаг-секции)
    var dbgToggle: NSMenuItem!
    var dbgItems: [NSMenuItem] = []
    var dbgState: NSMenuItem!, dbgEnergy: NSMenuItem!, dbgBoredom: NSMenuItem!
    var dbgHunger: NSMenuItem!, dbgMood: NSMenuItem!
    var engine: CatEngine = ReflexEngine()
    var engineReflexItem: NSMenuItem!, engineUtilityItem: NSMenuItem!

    let sets: [String: [(Int, Int)]] = [
        "idle":    [(3, 3)],
        "alert":   [(7, 3)],
        "scratch": [(5, 0), (6, 0), (7, 0)],
        "sleep":   [(2, 0), (2, 1)],
        "held":    [(3, 1), (5, 2)],            // болтается ногами при переносе
        "fall":    [(1, 2), (1, 3)],            // барахтается лапками в падении
        "hang":    [(1, 2)],                    // висит на курсоре — вытянутые лапы
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
        // настроение дня (детерминированно по дню года → меняется день ото дня)
        let day = Calendar.current.ordinality(of: .day, in: .year, for: Date()) ?? 0
        mood = Mood.allCases[day % Mood.allCases.count]
        restoreState()   // восстановить потребности, позицию и корм
        engine = makeEngine(UserDefaults.standard.string(forKey: "neko.engine") ?? "utility")
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
        win.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeCatIcon()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Pour kibble (⌃⌥⌘X)", action: #selector(feedMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Clear food", action: #selector(clearFoodMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Toss a yarn ball", action: #selector(tossYarnMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Remove yarn ball", action: #selector(removeYarnMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Go for a walk", action: #selector(walkMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Check for updates", action: #selector(checkUpdatesMenu), keyEquivalent: ""))
        let autoItem = NSMenuItem(title: "Auto-update", action: #selector(toggleAutoUpdate), keyEquivalent: "")
        autoItem.state = autoUpdate ? .on : .off
        menu.addItem(autoItem)
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About Neko", action: #selector(aboutMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Today's mood: \(mood.label)", action: nil, keyEquivalent: ""))  // приятная строка для всех
        menu.addItem(NSMenuItem(title: "Neko \(VERSION)", action: nil, keyEquivalent: ""))

        // Дебаг-секция — ТОЛЬКО при спец-запуске (--debug / NEKO_DEBUG=1). В обычной сборке её нет.
        if debugBuild {
            menu.addItem(.separator())
            dbgToggle = NSMenuItem(title: "Debug info", action: #selector(toggleDebug), keyEquivalent: "")
            dbgToggle.state = debug ? .on : .off
            menu.addItem(dbgToggle)
            dbgState   = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            dbgEnergy  = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            dbgBoredom = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            dbgHunger  = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            dbgMood    = NSMenuItem(title: "", action: nil, keyEquivalent: "")
            dbgItems = [dbgState, dbgEnergy, dbgBoredom, dbgHunger, dbgMood]
            for it in dbgItems { it.isEnabled = false; it.isHidden = !debug; menu.addItem(it) }
            let copyItem = NSMenuItem(title: "Copy state", action: #selector(copyDebugState), keyEquivalent: "")
            copyItem.isHidden = !debug
            dbgItems.append(copyItem)   // прячется/показывается вместе с дебагом
            menu.addItem(copyItem)

            menu.addItem(.separator())
            engineReflexItem  = NSMenuItem(title: "Engine: Reflex",  action: #selector(setEngineReflex),  keyEquivalent: "")
            engineUtilityItem = NSMenuItem(title: "Engine: Utility", action: #selector(setEngineUtility), keyEquivalent: "")
            engineReflexItem.state  = engine.label == "reflex"  ? .on : .off
            engineUtilityItem.state = engine.label == "utility" ? .on : .off
            menu.addItem(engineReflexItem)
            menu.addItem(engineUtilityItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        menu.delegate = self
        statusItem.menu = menu
        refreshDebug()

        registerFoodHotkey()
        enter(.sleep)
        // .common — чтобы кот продолжал двигаться при открытом меню
        let tickT = Timer(timeInterval: TICK, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tickT, forMode: .common)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.saveState() }
        // проверка обновлений при запуске и раз в 6 часов
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkForUpdates() }
        Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates() }

        if CommandLine.arguments.contains("--demo-walk") {   // разовый показ ухода
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in self?.startWalkabout() }
        }

        // App Translocation: запущен из временной копии → авто-обновление не сработает, подскажем
        if Bundle.main.bundlePath.contains("/AppTranslocation/") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                self?.alert("Tip: drag Neko into your Applications folder (from the disk image).\n\nRight now macOS runs it from a temporary copy, so it can't auto-update.")
            }
        }
    }

    // Значок менюбара — голова кота, вырезанная из кадра (3,3) спрайта
    func makeCatIcon() -> NSImage {
        // голова с замкнутым снизу контуром, line-art template (как иконка приложения)
        guard let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!) else { return NSImage() }
        let yTop = 99, yBot = 113, xL = 100, xR = 125
        let hw = xR - xL, hh = yBot - yTop + 1
        func px(_ x: Int, _ y: Int) -> Int {   // 0 пусто, 1 белый, 2 чёрный
            guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y) else { return 0 }
            if c.alphaComponent < 0.4 { return 0 }
            let lum = 0.3*c.redComponent + 0.59*c.greenComponent + 0.11*c.blueComponent
            return lum < 0.5 ? 2 : 1
        }
        var g = Array(repeating: Array(repeating: 0, count: hw), count: hh + 1)
        for ry in 0..<hh { for rx in 0..<hw { g[ry][rx] = px(xL + rx, yTop + ry) } }
        for ry in 0..<hh { for rx in 0..<hw where g[ry][rx] == 1 {   // замкнуть низ
            if g[ry + 1][rx] == 0 { g[ry + 1][rx] = 2 }
        }}
        var minX = hw, maxX = 0, minY = hh + 1, maxY = 0
        for y in 0..<(hh+1) { for x in 0..<hw where g[y][x] != 0 {
            minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
        }}
        let cw = maxX - minX + 1, ch = maxY - minY + 1
        // мелкая 1:1 картинка с заливкой (белый кот + чёрный контур), потом масштаб nearest
        let small = NSImage(size: NSSize(width: cw, height: ch))
        small.lockFocus()
        for y in 0..<ch { for x in 0..<cw {
            let v = g[minY + y][minX + x]
            if v == 0 { continue }
            (v == 2 ? NSColor.black : NSColor.white).setFill()
            NSRect(x: CGFloat(x), y: CGFloat(ch - 1 - y), width: 1, height: 1).fill()
        }}
        small.unlockFocus()
        let h: CGFloat = 18, w = h * CGFloat(cw) / CGFloat(ch)
        let img = NSImage(size: NSSize(width: w, height: h))
        img.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        small.draw(in: NSRect(x: 0, y: 0, width: w, height: h))
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
    func dragBegan() { dragging = true; clinging = false; flySpin = 0; flyRot = 0; eating = false; eatingRef = nil; iv.image = frame("held", 0) }
    func dragEnded() {
        dragging = false
        x = win.frame.origin.x + SIZE / 2
        fallY = win.frame.origin.y + SIZE / 2   // откуда падать
        fallVx = max(-42, min(42, iv.throwVel.x * 0.55))      // бросок по параболе (горизонталь шире)
        fallVy = -max(-28, min(28, iv.throwVel.y * 0.55))     // вертикаль скромнее — кот не улетает в космос
        flyHang = false                         // бросили рукой — барахтается лапами
        st = .falling                           // мягко приземлится на лапы (без отскока)
    }

    // Висит на курсоре как настоящий маятник с движущимся подвесом:
    //   θ'' = −(g/L)·sinθ − (a_пивота/L)·cosθ − c·θ'   (полу-неявный Эйлер)
    // Срывается, если поднять выше нижней трети ИЛИ сильно раскачать (улетает по параболе, крутясь).
    func clingStep() {
        let s = NSScreen.main ?? NSScreen.screens[0]
        let m = NSEvent.mouseLocation
        clingTicks += 1
        let dt = CGFloat(TICK)
        let L = SIZE * 0.5                                   // длина «нити» (курсор → центр кота)
        let g: CGFloat = 800                                // «гравитация» (период ≈ 1.3 c)
        let damp: CGFloat = 2.0                             // сопротивление воздуха

        // ускорение подвеса (курсора)
        let pivotV = (m.x - clingPrevX) / dt
        let pivotA = (pivotV - clingPivotV) / dt
        clingPrevX = m.x; clingPivotV = pivotV

        let th = Double(clingAngle)
        let acc = -(g / L) * CGFloat(sin(th)) - (pivotA / L) * CGFloat(cos(th)) - damp * clingVel
        clingVel += acc * dt                                // θ' (рад/с)
        clingAngle = max(-1.5, min(1.5, clingAngle + clingVel * dt))

        let cx = m.x + L * CGFloat(sin(Double(clingAngle)))
        let cy = m.y - L * CGFloat(cos(Double(clingAngle)))

        // сильно раскачали → срывается и летит по параболе, закручиваясь
        if clingTicks > 12 && abs(clingVel) > 7 {
            clinging = false
            x = cx; fallY = cy
            let tang = clingVel * L * dt                     // тангенциальная скорость (px/тик)
            fallVx = tang * CGFloat(cos(Double(clingAngle)))
            fallVy = -tang * CGFloat(sin(Double(clingAngle)))
            flySpin = clingVel * 1.5                         // закрутка в воздухе
            flyHang = true                                   // летит в позе висения
            st = .falling
            return
        }
        // подняли выше трети экрана → просто отцепился (без закрутки)
        if clingTicks > 4 && m.y > s.frame.minY + s.frame.height / 3 {
            clinging = false
            x = cx; fallY = cy; fallVx = 0; fallVy = 0; flySpin = 0; flyHang = true
            iv.frameCenterRotation = 0
            st = .falling
            return
        }
        x = cx
        win.setFrameOrigin(NSPoint(x: cx - SIZE / 2, y: cy - SIZE / 2))
        // поворот спрайта вокруг ЦЕНТРА на θ → верхняя точка (между лапами) попадает в курсор-пивот
        iv.frameCenterRotation = clingAngle * 180 / CGFloat.pi
        iv.image = frame("hang", 0)                          // висит с вытянутыми лапами
        anim += 1
    }

    // MARK: состояние

    func tick() {
        updateKibbles()                     // корм падает всегда
        updateYarn()                        // клубок катается/отскакивает
        if dragging {                       // пока несут — болтает ногами
            iv.image = frame("held", anim / 3)
            anim += 1
            return
        }
        if clinging { clingStep(); return } // висит на курсоре (поймал в прыжке)

        if st == .falling {                 // летит по параболе и мягко садится (без отскока)
            let ground = bottomY()
            let top = (NSScreen.main ?? NSScreen.screens[0]).frame.maxY - SIZE / 2
            fallVy += 6                      // гравитация (короткий реалистичный полёт)
            fallY -= fallVy
            x += fallVx                      // горизонтальный полёт
            fallVx *= 0.985                  // воздух
            let lo = leftEdge(), hi = rightEdge()
            if x < lo { x = lo; fallVx = 0 } // о стену — гасим, не отскакиваем
            if x > hi { x = hi; fallVx = 0 }
            if fallY > top { fallY = top; if fallVy < 0 { fallVy = 0 } }   // не выше экрана
            if flySpin != 0 {                    // закрутка в воздухе (после срыва с раскачки)
                flyRot += flySpin; flySpin *= 0.97
                iv.frameCenterRotation = flyRot
            }
            if fallY <= ground {
                fallY = ground
                fallVx = 0
                flySpin = 0; flyRot = 0; flyHang = false; iv.frameCenterRotation = 0   // приземлился — выпрямился
                enter(.idle)
                iv.image = frame("idle", 0)
            } else {
                iv.image = flyHang ? frame("hang", 0)        // слетел с курсора — поза висения
                                   : frame("fall", anim / 2) // бросили — дрыгает лапками
            }
            win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: fallY - SIZE / 2))
            anim += 1
            return
        }
        engine.step(self)                   // мозг+поза: Reflex или Utility (физика/драг/падение — общие выше)
    }


    @objc func walkMenu() { startWalkabout() }

    // MARK: - Обновления (GitHub Releases, публичный репо)
    var autoUpdate: Bool {
        get { (UserDefaults.standard.object(forKey: "neko.autoUpdate") as? Bool) ?? true }
        set { UserDefaults.standard.set(newValue, forKey: "neko.autoUpdate") }
    }

    func versionTuple(_ s: String) -> [Int] {
        s.replacingOccurrences(of: "v", with: "").split(separator: ".").map { Int($0) ?? 0 }
    }
    func isNewer(_ tag: String) -> Bool {
        let a = versionTuple(tag), b = versionTuple(VERSION)
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }

    @objc func checkUpdatesMenu() { checkForUpdates(manual: true) }

    @objc func aboutMenu() {
        let a = NSAlert()
        a.messageText = "Neko \(VERSION)"
        a.informativeText = """
        A calm desktop cat for macOS.

        The cat sprite is the classic “oneko” / Neko (1989 Macintosh desk accessory and \
        the X11 oneko). Sprite sheet from adryd325/oneko.js — all credit for the artwork \
        goes to its original authors.
        """
        a.addButton(withTitle: "OK")
        a.addButton(withTitle: "oneko.js on GitHub")
        if a.runModal() == .alertSecondButtonReturn,
           let url = URL(string: "https://github.com/adryd325/oneko.js") {
            NSWorkspace.shared.open(url)
        }
    }

    @objc func toggleAutoUpdate(_ sender: NSMenuItem) {
        autoUpdate.toggle()
        sender.state = autoUpdate ? .on : .off
    }

    @objc func toggleDebug() {
        debug.toggle()
        UserDefaults.standard.set(debug, forKey: "neko.debug")
        dbgToggle.state = debug ? .on : .off
        for it in dbgItems { it.isHidden = !debug }
        refreshDebug()
    }

    @objc func setEngineReflex()  { switchEngine("reflex") }
    @objc func setEngineUtility() { switchEngine("utility") }
    func switchEngine(_ name: String) {
        UserDefaults.standard.set(name, forKey: "neko.engine")
        engine = makeEngine(name)
        enter(.idle)   // чистый сброс переходных флагов при смене движка
        engineReflexItem?.state  = name == "reflex"  ? .on : .off
        engineUtilityItem?.state = name == "utility" ? .on : .off
    }

    @objc func copyDebugState() {
        let s = """
        neko \(VERSION)
        engine: \(engine.label)
        state: \(st.label)
        energy: \(String(format: "%.2f", energy))
        boredom: \(String(format: "%.2f", boredom))
        hunger: \(String(format: "%.2f", hunger))
        mood: \(mood.label)
        """
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.setString(s, forType: .string)
    }

    func refreshDebug() {
        guard debugBuild, debug, dbgState != nil else { return }
        dbgState.title   = "state: \(st.label)"
        dbgEnergy.title  = String(format: "energy: %.2f", energy)
        dbgBoredom.title = String(format: "boredom: %.2f", boredom)
        dbgHunger.title  = String(format: "hunger: %.2f", hunger)
        dbgMood.title    = "mood: \(mood.label)"
    }

    // обновляем дебаг-цифры в момент открытия меню
    func menuWillOpen(_ menu: NSMenu) { refreshDebug() }

    func checkForUpdates(manual: Bool = false) {
        let url = URL(string: "https://api.github.com/repos/\(REPO)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                if manual { DispatchQueue.main.async { self.alert("Couldn't check for updates") } }
                return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".zip") }
            DispatchQueue.main.async {
                if self.isNewer(tag), let zip = zip {
                    if self.autoUpdate {
                        self.installUpdate(zip)
                    } else {
                        let a = NSAlert()
                        a.messageText = "A new version \(tag) is available"
                        a.informativeText = "Update Neko now?"
                        a.addButton(withTitle: "Update"); a.addButton(withTitle: "Later")
                        if a.runModal() == .alertFirstButtonReturn { self.installUpdate(zip) }
                    }
                } else if manual {
                    self.alert("You're on the latest version (\(VERSION))")
                }
            }
        }.resume()
    }

    func alert(_ text: String) {
        NSApp.activate(ignoringOtherApps: true)   // accessory-приложение: иначе окно висит за другими
        let a = NSAlert(); a.messageText = "Neko"; a.informativeText = text; a.runModal()
    }

    func installUpdate(_ zipURL: String) {
        let appPath = Bundle.main.bundlePath
        if appPath.contains("/AppTranslocation/") {   // macOS запустил из временной копии — подмена не сработает
            alert("Can't update: macOS is running Neko from a temporary copy.\n\nDrag Neko into your Applications folder (from the disk image), then it will update normally.")
            return
        }
        let pid = ProcessInfo.processInfo.processIdentifier
        DispatchQueue.global().async {
            // выполняем шаг и возвращаем статус (всё логируется в /tmp/neko_update.log)
            func sh(_ cmd: String) -> Int32 {
                let p = Process(); p.launchPath = "/bin/sh"
                p.arguments = ["-c", "exec >> /tmp/neko_update.log 2>&1; set -x; " + cmd]
                try? p.run(); p.waitUntilExit(); return p.terminationStatus
            }
            func fail(_ msg: String) { DispatchQueue.main.async { self.alert("Update failed — \(msg)") } }

            // скачиваем и распаковываем, ПОКА приложение живо → ошибки видны пользователю
            _ = sh("rm -rf /tmp/neko_up /tmp/neko_up.zip && mkdir -p /tmp/neko_up")
            if sh("/usr/bin/curl -fsSL -o /tmp/neko_up.zip '\(zipURL)'") != 0 { fail("couldn't download"); return }
            if sh("/usr/bin/ditto -x -k /tmp/neko_up.zip /tmp/neko_up") != 0 { fail("couldn't unpack"); return }
            if sh("test -n \"$(/usr/bin/find /tmp/neko_up -maxdepth 3 -name Neko.app | head -1)\"") != 0 { fail("bad package"); return }

            // пакет ок — подменяем и перезапускаемся ПОСЛЕ выхода приложения (отдельный процесс переживёт наш выход)
            let swap = """
            exec >> /tmp/neko_update.log 2>&1; set -x
            NEW=$(/usr/bin/find /tmp/neko_up -maxdepth 3 -name Neko.app | head -1)
            i=0; while kill -0 \(pid) 2>/dev/null && [ $i -lt 100 ]; do sleep 0.1; i=$((i+1)); done
            rm -rf "\(appPath).old"; mv "\(appPath)" "\(appPath).old"
            /usr/bin/ditto "$NEW" "\(appPath)" || { mv "\(appPath).old" "\(appPath)"; exit 1; }
            rm -rf "\(appPath).old"
            /usr/bin/xattr -dr com.apple.quarantine "\(appPath)" 2>/dev/null
            /usr/bin/open "\(appPath)"
            """
            let p = Process(); p.launchPath = "/bin/sh"; p.arguments = ["-c", swap]
            try? p.run()
            DispatchQueue.main.async { NSApp.terminate(nil) }
        }
    }

    // MARK: - Сохранение состояния (переживает перезапуск/обновление)
    func saveState() {
        let d = UserDefaults.standard
        d.set(energy, forKey: "neko.energy")
        d.set(boredom, forKey: "neko.boredom")
        d.set(hunger, forKey: "neko.hunger")
        d.set(Double(x), forKey: "neko.x")
        let arr = kibbles.filter { $0.landed }.map {
            ["x": Double($0.x), "y": Double($0.y), "eaten": $0.eaten, "max": $0.maxBites]
        }
        d.set(arr, forKey: "neko.kibbles")
    }
    func restoreState() {
        let d = UserDefaults.standard
        if d.object(forKey: "neko.energy") != nil {
            energy = min(1, max(0, d.double(forKey: "neko.energy")))
            boredom = min(1, max(0, d.double(forKey: "neko.boredom")))
            hunger = min(1, max(0, d.double(forKey: "neko.hunger")))   // старое сохранение могло быть сырым счётчиком
            if let xx = d.object(forKey: "neko.x") as? Double { x = CGFloat(xx) }
        }
        if let arr = d.array(forKey: "neko.kibbles") as? [[String: Any]] {
            for k in arr {
                let kx = CGFloat(k["x"] as? Double ?? 0)
                let ky = CGFloat(k["y"] as? Double ?? 0)
                makeKibble(x: kx, y: ky, maxBites: k["max"] as? Int ?? 4,
                           eaten: k["eaten"] as? Int ?? 0, landed: true)
            }
        }
    }
    func applicationWillTerminate(_ n: Notification) { saveState() }

    func startWalkabout() {        // уйти гулять за стену (вызывается сам / для демо)
        guard !goingAway && !leaving, st != .away, st != .digging, st != .falling else { return }
        goingAway = true; toFood = false; awayLeft = Bool.random()
        targetX = awayLeft ? leftEdge() : rightEdge()
        enter(.walk)
    }

    // MARK: корм
    @objc func feedMenu() { dropKibble() }

    @objc func clearFoodMenu() {
        for k in kibbles { k.win.orderOut(nil) }
        kibbles.removeAll()
        eating = false; eatingRef = nil
    }

    // MARK: клубок
    let YSIZE: CGFloat = 28
    @objc func tossYarnMenu() {
        let s = NSScreen.main ?? NSScreen.screens[0]
        let m = NSEvent.mouseLocation
        if yarn == nil { makeYarn(x: min(max(m.x, s.frame.minX + 10), s.frame.maxX - 10), y: m.y) }
        if let k = yarn { k.vx = CGFloat.random(in: -16...16); k.vy = 6; k.landed = false }  // придать движение
    }
    @objc func removeYarnMenu() { yarn?.win.orderOut(nil); yarn = nil; toPlay = false }

    @discardableResult
    func makeYarn(x: CGFloat, y: CGFloat) -> Yarn {
        let w = NekoWindow(contentRect: NSRect(x: 0, y: 0, width: YSIZE, height: YSIZE),
                           styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2)
        w.ignoresMouseEvents = false
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let v = YarnView(frame: NSRect(x: 0, y: 0, width: YSIZE, height: YSIZE))
        let palette: [(NSColor, NSColor)] = [   // (мяч, нитки) — разный цвет каждый раз
            (rgb(255,120,170), rgb(210,80,130)),   // розовый
            (rgb(120,170,255), rgb(70,110,210)),   // голубой
            (rgb(130,220,170), rgb(70,160,110)),   // мятный
            (rgb(255,205,100), rgb(210,150,50)),   // жёлтый
            (rgb(180,150,255), rgb(120,90,210)),   // фиолетовый
            (rgb(255,160,110), rgb(210,110,60)),   // оранжевый
        ]
        let pick = palette.randomElement()!
        v.ball = pick.0; v.thread = pick.1
        w.contentView = v
        w.setFrameOrigin(NSPoint(x: x - YSIZE / 2, y: y - YSIZE / 2))
        w.orderFrontRegardless()
        let k = Yarn(win: w, view: v, x: x, y: y)
        v.onBegan = { [weak k] in k?.dragging = true; k?.vx = 0; k?.vy = 0 }
        v.onMoved = { [weak k] o in
            guard let k = k else { return }
            let nx = o.x + self.YSIZE / 2, ny = o.y + self.YSIZE / 2
            k.vx = max(-40, min(40, nx - k.x)); k.vy = max(-40, min(40, ny - k.y))   // инерция руки
            k.x = nx; k.y = ny
        }
        v.onEnded = { [weak k] in k?.dragging = false; k?.landed = false }   // бросок
        yarn = k
        return k
    }

    func updateYarn() {
        guard let k = yarn, !k.dragging else { return }
        let s = NSScreen.main ?? NSScreen.screens[0]
        let g = s.frame.minY + YSIZE / 2
        k.vy -= 2.0                          // гравитация
        k.x += k.vx; k.y += k.vy
        if k.y <= g {                        // отскок от пола, потом покой
            k.y = g
            k.vy = abs(k.vy) > 3 ? abs(k.vy) * 0.4 : 0
        }
        k.vx *= 0.97                         // качение с трением
        if abs(k.vx) < 0.2 { k.vx = 0 }
        if k.x < s.frame.minX + YSIZE / 2 { k.x = s.frame.minX + YSIZE / 2; k.vx = -k.vx * 0.6 }
        if k.x > s.frame.maxX - YSIZE / 2 { k.x = s.frame.maxX - YSIZE / 2; k.vx = -k.vx * 0.6 }
        k.landed = (k.y <= g + 0.5 && k.vx == 0 && k.vy == 0)
        if k.vx != 0 {                              // катится — вращаем спрайт
            k.angle -= Double(k.vx) / Double(YSIZE / 2) * 180 / .pi
            k.view.frameCenterRotation = CGFloat(k.angle)
        }
        k.win.setFrameOrigin(NSPoint(x: k.x - YSIZE / 2, y: k.y - YSIZE / 2))
    }

    // высыпать один катышек из позиции курсора (падает на пол)
    func dropKibble() {
        if kibbles.count >= 80 { return }   // лимит, чтобы не наплодить окон
        let s = NSScreen.main ?? NSScreen.screens[0]
        let m = NSEvent.mouseLocation
        let cx = min(max(m.x, s.frame.minX + 8), s.frame.maxX - 8)
        makeKibble(x: cx, y: m.y - 7, maxBites: Int.random(in: 3...4))
    }

    @discardableResult
    func makeKibble(x: CGFloat, y: CGFloat, maxBites: Int, eaten: Int = 0, landed: Bool = false) -> Kibble {
        let sz: CGFloat = 14
        let w = NekoWindow(contentRect: NSRect(x: 0, y: 0, width: sz, height: sz),
                           styleMask: .borderless, backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.hasShadow = false
        w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.dockWindow)) + 2) // спереди кота
        w.ignoresMouseEvents = false   // можно перекладывать
        w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        let dot = KibbleDot(frame: NSRect(x: 0, y: 0, width: sz, height: sz))
        w.contentView = dot
        w.setFrameOrigin(NSPoint(x: x - sz / 2, y: y))
        w.orderFrontRegardless()
        let kib = Kibble(win: w, dot: dot, x: x, y: y, maxBites: maxBites)
        kib.eaten = eaten; kib.landed = landed
        dot.stage = min(KibbleDot.stages.count - 1, Int(Double(eaten) / Double(maxBites) * Double(KibbleDot.stages.count)))
        dot.onBegan = { [weak kib] in kib?.dragging = true; kib?.landed = false; kib?.vx = 0; kib?.vy = 0 }
        dot.onMoved = { [weak kib] o in
            guard let kib = kib else { return }
            let nx = o.x + sz / 2
            kib.vx = max(-45, min(45, nx - kib.x))     // инерция от движения руки
            kib.vy = max(-45, min(45, o.y - kib.y))
            kib.x = nx; kib.y = o.y
        }
        dot.onEnded = { [weak kib] in
            guard let kib = kib else { return }
            kib.dragging = false; kib.landed = false
            let mid = (NSScreen.main ?? NSScreen.screens[0]).frame.midY
            kib.canEscape = kib.y > mid     // из верхней половины — улетит; из нижней — отскочит
        }
        kibbles.append(kib)
        return kib
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
