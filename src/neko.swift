import Cocoa
import Carbon.HIToolbox

// Спокойный oneko: живёт на нижней кромке, много спит, изредка мягко гуляет.
// Корм по ⌃⌥⌘X — у курсора насыпается горка; кот придёт есть, когда сам проснётся.
// Кота можно перетащить мышью.
let VERSION = "1.1.7"
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
    var hoverTicks = 0             // (устар.) ранее: зависание мыши над котом
    var huntAimY: CGFloat = 0      // y-цель прыжка (точка курсора)
    var huntInterest = 0.0         // накопленное «желание прыгнуть» (растёт от движения курсора рядом)
    var huntSat = 0.0              // насыщение охотой: пару раз прыгнул — приелось (порог растёт), спадает со временем
    var hunting = false            // в полёте охотничьего прыжка: ловит курсор + наклон по траектории
    var clinging = false           // висит на курсоре
    var clingPrevX: CGFloat = 0    // прошлый x курсора (для раскачки)
    var clingAngle: CGFloat = 0    // угол маятника
    var clingVel: CGFloat = 0      // угловая скорость маятника
    var flySpin: CGFloat = 0       // закрутка в полёте (после срыва с раскачки)
    var flyRot: CGFloat = 0        // накопленный угол вращения в полёте
    var flyHang = false            // в полёте поза «висения» (вытянутые лапы), а не барахтанье
    var clingTicks = 0             // сколько висит (чтобы не срывался мгновенно при зацепе)
    var clingPivotV: CGFloat = 0   // скорость пивота-курсора (для ускорения подвеса)
    var clingPrevY: CGFloat = 0    // прошлый y курсора (для детекта неподвижности)
    var clingStill = 0             // сколько тиков курсор почти не двигается (→ сам спрыгнет)
    var hopOffset: CGFloat = 0     // подъём при прыжке (дуга)
    var lastMouseX: CGFloat = 0, lastMouseY: CGFloat = 0   // прошлая позиция курсора
    var mouseDelta: CGFloat = 0    // насколько курсор сдвинулся за тик (для побудки мышкой)
    var toFood = false         // спешит к корму
    var yarns: [Yarn] = []     // клубки (можно насыпать несколько), кот гоняется за ближайшим
    weak var lastPokedYarn: Yarn?  // последний новый/тронутый рукой мяч — к нему интерес выше
    var lastYarnPalette = -1   // чтобы подряд не выпадал тот же цвет
    var toPlay = false         // спешит к клубку поиграть
    var playSat = 0.0          // 0..1 — насколько клубок надоел (растёт от игры, спадает со временем)
    var playTired = false      // наигрался — отдыхает, пока интерес не восстановится (гистерезис)
    var playDir: CGFloat = 1   // в какую сторону толкнуть в этот раз (чередуется)
    var playCool = 0           // пауза после удара по мячу — не семенить вокруг, дать ему отлететь
    var returningToSleep = false  // вернулся с прогулки уставшим → лечь спать на экране
    var leaping = false           // прыжок между мониторами (баллистика на другой экран)
    weak var leapScreen: NSScreen? // монитор-назначение прыжка
    var leapTicks = 0             // тики в текущей дуге прыжка
    var leapSteps = 18            // сколько тиков длится текущая дуга
    var leapDown = false          // прыжок вниз (спрыгивание) — другая раскадровка
    var leapWait = 0              // «присматривается» перед прыжком (тики)
    var leapBounce = false        // прыжок вверх с отскоком от стены
    var leapPhase = 0             // фаза bounce-прыжка: 0 = к стене, 1 = от стены наверх
    var leapTX: CGFloat = 0       // финальная цель по X (для фазы 2 bounce)
    var leapTY: CGFloat = 0       // финальная цель по Y (пол монитора-назначения)
    var leapTan: CGFloat = 0      // сглаженная касательная (чтобы наклон в полёте был под контролем)
    var leapWait0 = 1             // исходная длительность фазы подготовки (для под-фаз прицел→присед)
    var leapSalto = false         // прыжок от стены через сальто (иногда — для красоты)
    var leapSpin: CGFloat = 0     // накопленный угол сальто
    var leapSpinStep: CGFloat = 0 // прирост угла сальто за тик (оборот завершается к вершине)
    var comeHereSpeed: CGFloat = 0 // скорость забега с края при «Come here» (0 = обычная ходьба)
    weak var comeHereJumpScreen: NSScreen? // «Come here»: добежал на свой монитор → прыгнуть на этот (званый)
    var huntAir = 0               // тики в охотничьем полёте (чтобы не «прилипал» к курсору мгновенно)
    var eatingRef: Kibble?     // что грызёт сейчас
    var biteTick = 0           // тики до следующего укуса
    let ZOOM: CGFloat = 13     // скорость беготни
    let FOOD_SPEED: CGFloat = 13 // быстрый бег к корму/клубку (как в zoomies)
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
        || UserDefaults.standard.bool(forKey: "neko.forceDebug")   // запомненный дебаг на этом маке
    var debug = UserDefaults.standard.bool(forKey: "neko.debug")  // показывать ли строки (внутри дебаг-секции)
    var dbgToggle: NSMenuItem!
    var dbgItems: [NSMenuItem] = []
    var dbgState: NSMenuItem!, dbgEnergy: NSMenuItem!, dbgBoredom: NSMenuItem!
    var dbgHunger: NSMenuItem!, dbgMood: NSMenuItem!
    var engine: CatEngine = ReflexEngine()
    var engineReflexItem: NSMenuItem!, engineUtilityItem: NSMenuItem!
    var forceDebugItem: NSMenuItem!
    var spacesItem: NSMenuItem!
    var spacesExperiment = false   // режим Spaces, снятый из настроек на старте (см. applicationDidFinishLaunching)
    var moodItem: NSMenuItem!    // строка «Today's mood» — обновляется при смене настроения
    var lastSaveTS = Date().timeIntervalSince1970   // время последнего сейва — для отдыха «вне компа»
    var bootState: St = .idle    // в каком состоянии стартовать (восстанавливается из сейва)
    var dbgMenuTimer: Timer?     // live-обновление цифр, пока меню открыто
    var checkRow: MenuRowView!, autoRow: MenuRowView!   // нативные строки апдейта (меню не закрывают)

    let sets: [String: [(Int, Int)]] = [
        "idle":    [(3, 3)],
        "alert":   [(7, 3)],
        "scratch": [(5, 0), (6, 0), (7, 0)],
        "sleep":   [(2, 0), (2, 1)],
        "held":    [(3, 1), (5, 2)],            // болтается ногами при переносе
        "fall":    [(1, 2), (1, 3)],            // барахтается лапками в падении
        "hang":    [(1, 2)],                    // висит на курсоре — вытянутые лапы
        "jump":    [(3, 1), (0, 2), (3, 0), (5, 1), (5, 2)],  // прыжок-разбег (разбег→взлёт→полёт→приземление)
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
        // Spaces: надёжно — canJoinAllSpaces (везде, всегда с тобой); эксперимент — закреплён за десктопом (бродит)
        spacesExperiment = UserDefaults.standard.bool(forKey: "neko.spacesExperiment")   // зафиксировать режим на старте
        win.collectionBehavior = spacesExperiment
            ? [.fullScreenAuxiliary, .stationary, .ignoresCycle]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
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
        restoreState()   // восстановить потребности, позицию, монитор и корм
        y = bottomY()    // пересчитать пол под восстановленный монитор
        engine = makeEngine(UserDefaults.standard.string(forKey: "neko.engine") ?? "utility")
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
        win.orderFrontRegardless()

        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.button?.image = makeCatIcon()
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "🍚 Pour kibble (⌃⌥⌘X)", action: #selector(feedMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🧹 Clear food", action: #selector(clearFoodMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🧶 Toss a yarn ball", action: #selector(tossYarnMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🚫 Remove yarn ball", action: #selector(removeYarnMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🐾 Go for a walk", action: #selector(walkMenu), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "🔔 Come here!", action: #selector(comeHereMenu), keyEquivalent: ""))
        menu.addItem(.separator())
        menu.addItem(makeCheckUpdatesItem())   // кнопка + спиннер + статус, меню не закрывается
        menu.addItem(makeAutoUpdateItem())     // чекбокс, меню не закрывается
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "About Neko", action: #selector(aboutMenu), keyEquivalent: ""))
        moodItem = NSMenuItem(title: "Today's mood: \(mood.label)", action: nil, keyEquivalent: "")  // приятная строка для всех
        menu.addItem(moodItem)
        menu.addItem(NSMenuItem(title: "Neko \(VERSION)", action: nil, keyEquivalent: ""))

        // Дебаг-секция — ТОЛЬКО при спец-запуске (--debug / NEKO_DEBUG=1). В обычной сборке её нет.
        if debugBuild {
            menu.addItem(.separator())
            // тогглы — единый стиль (как Auto-update), клик НЕ закрывает меню
            let dbgRow = MenuRowView(title: "Debug info", width: 260, hasCheck: true)
            dbgRow.setChecked(debug)
            dbgRow.onClick = { [weak self, weak dbgRow] in
                guard let self else { return }
                self.debug.toggle(); UserDefaults.standard.set(self.debug, forKey: "neko.debug")
                for it in self.dbgItems { it.isHidden = !self.debug }
                self.refreshDebug(); dbgRow?.setChecked(self.debug)
            }
            let dbgRowItem = NSMenuItem(); dbgRowItem.view = dbgRow; menu.addItem(dbgRowItem)

            let forceRow = MenuRowView(title: "Always debug on this Mac", width: 260, hasCheck: true)
            forceRow.setChecked(UserDefaults.standard.bool(forKey: "neko.forceDebug"))
            forceRow.onClick = { [weak forceRow] in
                let v = !UserDefaults.standard.bool(forKey: "neko.forceDebug")
                UserDefaults.standard.set(v, forKey: "neko.forceDebug"); forceRow?.setChecked(v)
            }
            let forceRowItem = NSMenuItem(); forceRowItem.view = forceRow; menu.addItem(forceRowItem)

            let spacesRow = MenuRowView(title: "Spaces: wander mode (restart)", width: 260, hasCheck: true)
            spacesRow.setChecked(UserDefaults.standard.bool(forKey: "neko.spacesExperiment"))
            spacesRow.onClick = { [weak self, weak spacesRow] in
                guard let self else { return }
                let v = !UserDefaults.standard.bool(forKey: "neko.spacesExperiment")
                UserDefaults.standard.set(v, forKey: "neko.spacesExperiment"); spacesRow?.setChecked(v)
                self.relaunchSelf()
            }
            let spacesRowItem = NSMenuItem(); spacesRowItem.view = spacesRow; menu.addItem(spacesRowItem)

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
            let reflexRow = MenuRowView(title: "Engine: Reflex", width: 260, hasCheck: true)
            let utilityRow = MenuRowView(title: "Engine: Utility", width: 260, hasCheck: true)
            reflexRow.setChecked(engine.label == "reflex"); utilityRow.setChecked(engine.label == "utility")
            reflexRow.onClick = { [weak self, weak reflexRow, weak utilityRow] in
                self?.switchEngine("reflex"); reflexRow?.setChecked(true); utilityRow?.setChecked(false) }
            utilityRow.onClick = { [weak self, weak reflexRow, weak utilityRow] in
                self?.switchEngine("utility"); utilityRow?.setChecked(true); reflexRow?.setChecked(false) }
            let reflexItem = NSMenuItem(); reflexItem.view = reflexRow; menu.addItem(reflexItem)
            let utilityItem = NSMenuItem(); utilityItem.view = utilityRow; menu.addItem(utilityItem)

            menu.addItem(.separator())
            let forceItem = NSMenuItem(title: "Force state", action: nil, keyEquivalent: "")
            let forceMenu = NSMenu()
            let states: [(String, String)] = [
                ("Sleep", "sleep"), ("Idle", "idle"), ("Walk", "walk"),
                ("Zoomies", "zoomies"), ("Walkabout (away)", "away"), ("Dig", "dig"),
                ("Hunt cursor", "hunt"), ("Play (spawn yarn)", "play"), ("Fall", "fall"),
                ("Eat (reset hunger)", "eat"),
                ("Leap ↑ monitor", "leapup"), ("Leap ↑ w/ wall bounce", "leapbounce"),
                ("Leap ↓ monitor", "leapdown"), ("Leap → other monitor", "leap"),
            ]
            for (title, key) in states {
                let it = NSMenuItem(title: title, action: #selector(forceState(_:)), keyEquivalent: "")
                it.representedObject = key
                forceMenu.addItem(it)
            }
            forceItem.submenu = forceMenu
            menu.addItem(forceItem)
        }

        menu.addItem(.separator())
        menu.addItem(NSMenuItem(title: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q"))
        // нативные пункты (эмодзи-действия, инфо, Quit) — сдвинуть текст вправо к отступу кастомных строк
        for it in menu.items where it.view == nil && !it.isSeparatorItem && !it.title.isEmpty {
            it.title = "  " + it.title
        }
        menu.delegate = self
        statusItem.menu = menu
        refreshDebug()

        registerFoodHotkey()
        enter(bootState)               // восстановленное состояние, а не всегда сон
        if bootState == .walk { targetX = randomX() }   // прогулке нужна цель, иначе мгновенно «дойдёт»
        // .common — чтобы кот продолжал двигаться при открытом меню
        let tickT = Timer(timeInterval: TICK, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(tickT, forMode: .common)
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.saveState() }
        // проверка обновлений при запуске и раз в 6 часов
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) { [weak self] in self?.checkForUpdates() }
        Timer.scheduledTimer(withTimeInterval: 2 * 3600, repeats: true) { [weak self] _ in self?.checkForUpdates() }
        // настроение меняется несколько раз в день (каждые ~6 ч)
        Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { [weak self] _ in self?.rerollMood() }
        // ноут проснулся (крышку открыли) → начислить коту отдых за время сна системы
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(systemDidWake),
                                                          name: NSWorkspace.didWakeNotification, object: nil)
        // переключили рабочий стол (Space) → кот чаще «идёт за тобой» на активный десктоп
        NSWorkspace.shared.notificationCenter.addObserver(self, selector: #selector(spaceChanged),
                                                          name: NSWorkspace.activeSpaceDidChangeNotification, object: nil)
        // CSV-лог состояний раз в 5с (только в дебаге) — числовые кривые нужд для графиков
        Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in self?.logStateSample() }

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

    // === Экраны (мультимонитор) ===
    var homeScreen: NSScreen?                          // на каком мониторе кот «живёт» сейчас
    func curScreen() -> NSScreen {                     // валидируем (монитор могли отключить)
        if let h = homeScreen, NSScreen.screens.contains(where: { $0.frame == h.frame }) { return h }
        homeScreen = NSScreen.main; return homeScreen ?? NSScreen.screens[0]
    }
    func screenAt(_ p: NSPoint) -> NSScreen? { NSScreen.screens.first { NSMouseInRect(p, $0.frame, false) } }
    func cursorScreen() -> NSScreen? { screenAt(NSEvent.mouseLocation) }
    func neighborScreen(left: Bool) -> NSScreen? {     // монитор РЕАЛЬНО сбоку (не сверху/снизу): по X левее/правее + пересечение по вертикали
        let c = curScreen().frame
        return NSScreen.screens.filter { s in
            s.frame != c
            && (left ? s.frame.maxX <= c.minX + 2 : s.frame.minX >= c.maxX - 2)   // его X-диапазон сбоку, без горизонтального наложения
            && s.frame.minY < c.maxY && s.frame.maxY > c.minY                      // и есть перекрытие по вертикали (можно дойти пешком)
        }.min(by: { abs($0.frame.midX - c.midX) < abs($1.frame.midX - c.midX) })
    }
    // монитор СВЕРХУ/СНИЗУ (с перекрытием по X) — туда прыжком/спрыгиванием
    func verticalNeighbor(up: Bool) -> NSScreen? {
        let c = curScreen().frame
        return NSScreen.screens.filter { s in
            s.frame != c
            && (up ? s.frame.minY >= c.maxY - 2 : s.frame.maxY <= c.minY + 2)
            && s.frame.minX < c.maxX && s.frame.maxX > c.minX
        }.min(by: { abs($0.frame.midY - c.midY) < abs($1.frame.midY - c.midY) })
    }
    func anyOtherScreen() -> NSScreen? {                 // ближайший любой другой монитор
        let c = curScreen().frame
        return NSScreen.screens.filter { $0.frame != c }
            .min(by: { hypot($0.frame.midX-c.midX,$0.frame.midY-c.midY) < hypot($1.frame.midX-c.midX,$1.frame.midY-c.midY) })
    }

    // ось лётного кадра прыжка (флюгер): наклон = угол скорости − ось (как в раскадровках sprite-tools)
    func leapAxis(_ c: Int, _ r: Int) -> CGFloat {
        switch (c, r) { case (0,3): return 90; case (0,2): return 60; case (3,0): return 0; case (5,1): return -35; default: return 0 }
    }
    // дискретно-точная вертикальная скорость, чтобы за T тиков ровно прийти из fromY в toY
    // (интегратор: fallVy += 6; fallY -= fallVy → Σ 6i = 3T(T+1))
    func solveVy(from fromY: CGFloat, to toY: CGFloat, ticks T: Int) -> CGFloat {
        -((toY - fromY) / CGFloat(T) + 3 * CGFloat(T + 1))
    }
    // наклон спрайта по «флюгеру» с учётом зеркала: при flip нос смотрит в (180−ось),
    // поэтому наклон = касательная − (180−ось). Без зеркала — касательная − ось.
    func leapTilt(_ c: Int, _ r: Int, tangent: CGFloat, flip: Bool) -> CGFloat {
        let a = leapAxis(c, r)
        let base = flip ? (180 - a) : a
        var raw = tangent - base
        while raw > 180 { raw -= 360 }; while raw < -180 { raw += 360 }   // нормализуем
        return max(-90, min(90, raw))
    }
    // куда целиться по X на экране dst: в сторону, где БОЛЬШЕ места, на долю этого простора (с вариативностью).
    // у края → прыгает к центру; у центра → в чуть более просторную сторону; никогда не через весь экран на дальний край.
    func leapTargetX(on dst: NSScreen) -> CGFloat {
        let lo = dst.frame.minX + SIZE / 2, hi = dst.frame.maxX - SIZE / 2
        guard hi > lo else { return (lo + hi) / 2 }
        let cx = min(max(x, lo), hi)                       // текущий X, спроецированный на экран назначения
        let leftRoom = cx - lo, rightRoom = hi - cx
        let toRight = rightRoom >= leftRoom                 // в сторону, где простора больше
        let room = toRight ? rightRoom : leftRoom
        let dist = max(SIZE * 1.5, room * CGFloat.random(in: 0.3...0.65))   // доля простора + разброс → вариативность
        return min(max(toRight ? cx + dist : cx - dist, lo), hi)
    }
    // баллистика дуги ВВЕРХ: подняться до вершины (toY + clr), затем сесть ровно на toY в точке toX.
    // clr — небольшой запас над целью (1–2 роста), чтобы не выпрыгивать на пол-экрана.
    func upArc(fromX sx: CGFloat, fromY sy: CGFloat, toX tx: CGFloat, toY ty: CGFloat, clr: CGFloat) -> (vx: CGFloat, vy: CGFloat, steps: Int) {
        let g: CGFloat = 6
        let Hu = max(SIZE * 0.5, (ty - sy) + clr)          // высота подъёма до вершины
        let v0 = -(2 * g * Hu).squareRoot()                // стартовая вертикаль (вверх)
        let tUp = -v0 / g                                   // тиков до вершины
        let tDown = (2 * clr / g).squareRoot()              // тиков с вершины до пола
        let T = max(10, Int((tUp + tDown).rounded()))
        return ((tx - sx) / CGFloat(T), v0, T)
    }
    // запуск прыжка на другой монитор: баллистика к полу монитора-назначения
    func launchLeap(to screen: NSScreen, bounce: Bool = false) {
        toFood = false; toPlay = false; goingAway = false; leaving = false; eating = false; clinging = false; hunting = false
        flyHang = false; flySpin = 0; flyRot = 0; leapSpin = 0; leapSalto = false
        let ty = screen.frame.minY + SIZE / 2 - FOOT
        let tx = leapTargetX(on: screen)                  // в сторону, где больше места (с вариативностью)
        leapDown = ty < y
        leapScreen = screen; leapTicks = 0; leaping = true; leapBounce = false; leapPhase = 0
        leapTX = tx; leapTY = ty
        fallY = y
        if leapDown {
            // СПРЫГИВАНИЕ (раскадровка drop): 5,2 присматривается у края → 5,1 нос вниз → 5,2 на земле → 3,1.
            // Никакого подскока вверх — свободное падение с горизонтальным разгоном.
            // h = y - ty (>0); при v0=0 пройдём h = 3T(T+1) → решаем T.
            let h = y - ty
            let T = max(8, Int(((-1 + (1 + 4 * h / 3).squareRoot()) / 2).rounded()))
            leapSteps = T
            fallVx = (tx - x) / CGFloat(T)
            fallVy = 0                       // стартует с места — сначала присматривается (5,2), потом чпок вниз
            leapWait = 16                    // сидит у края и смотрит вниз перед прыжком
        } else if bounce, let wall = nearWallX() {
            // ПРЫЖОК С ОТСКОКОМ (раскадровка wall, в стиле Assassin's Creed):
            // фаза 0 — мощно к стене и кот достаёт её на ВОСХОДЯЩЕЙ дуге (ещё летит вверх),
            // фаза 1 — энергично отталкивается от стены наверх к монитору (иногда через сальто).
            leapBounce = true                            // сальто решаем на 2-й фазе (только если прыгает с запасом)
            let wy = y + (ty - y) * 0.5                  // контакт со стеной ~ на середине высоты
            let R = wy - y                                // подъём до контакта
            let apexRise = R * 1.4                        // вершина ВЫШЕ контакта → у стены ещё летит вверх
            let v0 = -(12 * apexRise).squareRoot()        // стартовая вертикаль (вверх)
            let disc = max(0, v0 * v0 - 12 * R)
            let TA = max(6, Int(((-v0 - disc.squareRoot()) / 6).rounded()))   // момент пересечения wy на ВОСХОДЯЩЕЙ ветви
            leapSteps = TA
            fallVx = (wall - x) / CGFloat(TA)
            fallVy = v0
            leapWait = 16                                 // собирается перед прыжком на стену
        } else {
            // ПРЯМОЙ ПРЫЖОК ВВЕРХ (раскадровка jump): 0,3 толчок → 0,2 → вершина 3,0 → 5,1 → 5,2 → 3,1.
            // Плоская парабола в сторону простора, небольшой запас вверх (1–2 роста).
            let clr = CGFloat.random(in: SIZE...(SIZE * 2))
            let arc = upArc(fromX: x, fromY: y, toX: tx, toY: ty, clr: clr)
            fallVx = arc.vx; fallVy = arc.vy; leapSteps = arc.steps
            leapWait = 16                                 // прицеливается и собирается перед прыжком
        }
        leapWait0 = max(1, leapWait)
        leapTan = CGFloat(atan2(Double(-(fallVy + 6)), Double(fallVx)) * 180 / .pi)   // старт сглаживания (с учётом первого тика гравитации)
        elog("leap", ["to": screenNumber(screen), "down": leapDown ? 1 : 0, "bounce": bounce ? 1 : 0])
    }
    // ближайшая боковая стена ТЕКУЩЕГО монитора (для отскока)
    func nearWallX() -> CGFloat? {
        let f = curScreen().frame
        let left = f.minX + SIZE / 2, right = f.maxX - SIZE / 2
        return (abs(x - left) < abs(x - right)) ? left : right
    }
    // кадр+наклон лётной дуги прыжка вверх (общая раскадровка для прямого прыжка и фаз отскока)
    func leapUpFrame(_ p: CGFloat, flip: Bool) {
        let c: Int, r: Int, tilt: Bool
        switch p {                                       // jump.png: 0,3 → 0,2 → 3,0 → 5,1 → 5,2
        case ..<0.16: (c, r, tilt) = (0, 3, false)       // толчок (не крутим)
        case ..<0.55: (c, r, tilt) = (0, 2, true)        // взлёт
        case ..<0.80: (c, r, tilt) = (3, 0, true)        // вершина
        case ..<1.00: (c, r, tilt) = (5, 1, true)        // снижение
        default:      (c, r, tilt) = (5, 2, false)       // посадка (не крутим)
        }
        iv.image = frameCell(c, r, flip: flip)
        iv.frameCenterRotation = tilt ? leapTilt(c, r, tangent: leapTan, flip: flip) : 0
    }
    // короткая дуга ОТ стены (раскадровка wall, фаза 2): 3,0 взлёт → 5,1 снижение → 5,2 посадка.
    // Без приседа/0,2 — кот уже оттолкнулся; меньше смен кадров → не дёргается на короткой дуге.
    func leapBounceFrame(_ p: CGFloat, flip: Bool) {
        let c: Int, r: Int, tilt: Bool
        switch p {
        case ..<0.45: (c, r, tilt) = (3, 0, true)        // взлёт от стены
        case ..<0.85: (c, r, tilt) = (5, 1, true)        // снижение
        default:      (c, r, tilt) = (5, 2, false)       // посадка
        }
        iv.image = frameCell(c, r, flip: flip)
        iv.frameCenterRotation = tilt ? leapTilt(c, r, tangent: leapTan, flip: flip) : 0
    }
    // приземление: гасит скорость не сидя, а пробежкой пары шагов по ходу полёта
    func leapLand(on dst: NSScreen) {
        homeScreen = dst
        y = dst.frame.minY + SIZE / 2 - FOOT; fallY = y
        x = min(max(leapTX, leftEdge()), rightEdge())     // ровно в намеченную точку (а не «куда успел») — без рывка к кромке
        iv.frameCenterRotation = 0; leaping = false; leapBounce = false; leapPhase = 0; leapSpin = 0
        returningToSleep = false                                    // приземлился бодро — не уходит сразу спать
        let dir: CGFloat = fallVx < 0 ? -1 : 1                       // добегает по инерции в сторону полёта
        let dist = CGFloat.random(in: SIZE * 0.8 ... SIZE * 1.8)
        targetX = min(max(x + dir * dist, leftEdge()), rightEdge())
        comeHereSpeed = 6                                            // бодрый добег, потом сам встанет в idle
        enter(.walk)
        iv.image = frameCell(3, 1, flip: fallVx < 0)                 // «гашу скорость»
    }
    // шаг прыжка между мониторами (отдельная физика с раскадровкой и наклоном; уверенный полёт по параболе)
    func leapStep() {
        guard let dst = leapScreen else { leaping = false; return }
        // фаза подготовки «прицеливается/собирается» (или короткий контакт со стеной) — окно не двигаем
        if leapWait > 0 {
            leapWait -= 1
            iv.frameCenterRotation = 0
            if leapBounce && leapPhase == 1 {                        // у стены: НЕ поза полёта, коротко оттолкнуться
                iv.image = frameCell(0, 3, flip: fallVx > 0)         // упёрся в стену, поджался к толчку
            } else if leapDown {
                iv.image = frameCell(5, 2, flip: leapTX < x)         // присматривается у края, мордой по ходу прыжка
            } else if leapBounce {                                   // присед к толчку в сторону стены
                iv.image = frameCell(0, 3, flip: fallVx < 0)
            } else {                                                 // прямой прыжок вверх: присед перед толчком (без алёрта)
                iv.image = frameCell(0, 3, flip: leapTX < x)
            }
            anim += 1
            return
        }
        leapTicks += 1
        fallVy += 6; fallY -= fallVy; x += fallVx
        let p = min(1, CGFloat(leapTicks) / CGFloat(leapSteps))
        let west = fallVx < 0
        // наклон = текущая касательная к траектории (без межтикового сглаживания: на вершине угол
        // заворачивается через ±180°, и сглаживание гнало бы его «длинным путём» → наклон не в попад).
        // нормализацию/зеркало берёт на себя leapTilt.
        leapTan = CGFloat(atan2(Double(-fallVy), Double(fallVx)) * 180 / .pi)

        if leapDown {                                    // drop: 5,1 нос вниз по дуге → 5,2 на земле
            if p < 0.85 {
                iv.image = frameCell(5, 1, flip: west)
                iv.frameCenterRotation = leapTilt(5, 1, tangent: leapTan, flip: west)
            } else {
                iv.image = frameCell(5, 2, flip: west); iv.frameCenterRotation = 0
            }
        } else if leapBounce && leapPhase == 0 {         // wall фаза 0: к стене, ЛИЦОМ к стене (зеркально)
            let toWall = west
            iv.image = frameCell(p < 0.5 ? 0 : 3, p < 0.5 ? 2 : 0, flip: toWall)
            iv.frameCenterRotation = leapTilt(p < 0.5 ? 0 : 3, p < 0.5 ? 2 : 0, tangent: leapTan, flip: toWall)
        } else if leapBounce && leapPhase == 1 && leapSalto && fallVy < 0 {   // сальто ТОЛЬКО на восходящей (вверху дуги)
            leapSpin += leapSpinStep                            // оборот завершается к вершине
            iv.frameCenterRotation = leapSpin
            iv.image = frameCell(0, 2, flip: west)              // поджался в комок
        } else if leapBounce && leapPhase == 1 {         // взлёт/снижение/посадка — нормальная ориентация (3,0→5,1→5,2)
            leapBounceFrame(p, flip: west)
        } else {                                         // прямой прыжок вверх — полная дуга jump
            leapUpFrame(p, flip: west)
        }

        // фаза 0 отскока завершается достижением стены → толчок наверх (фаза 1)
        if leapBounce && leapPhase == 0 && leapTicks >= leapSteps {
            leapPhase = 1
            x = nearWallX() ?? x                         // прижались к стене
            leapTX = leapTargetX(on: dst)                // от стены — в сторону простора (с вариативностью)
            // сальто — редкое (20%) и ТОЛЬКО когда отскок «с запасом» (высокая дуга); впритык — без сальто
            leapSalto = Double.random(in: 0..<1) < 0.2
            let clr = leapSalto ? CGFloat.random(in: SIZE * 2.5 ... SIZE * 4)   // высокий заброс — есть где крутить сальто
                                : CGFloat.random(in: SIZE ... SIZE * 2)         // обычный/впритык
            let arc = upArc(fromX: x, fromY: fallY, toX: leapTX, toY: leapTY, clr: clr)
            fallVx = arc.vx; fallVy = arc.vy; leapSteps = arc.steps; leapTicks = 0; leapSpin = 0
            let ascend = max(1, Int((-fallVy) / 6))      // тиков до вершины — за них и крутим полный оборот
            leapSpinStep = (fallVx < 0 ? 1 : -1) * 360 / CGFloat(ascend)
            leapTan = CGFloat(atan2(Double(-(fallVy + 6)), Double(fallVx)) * 180 / .pi)
            leapWait = 2; leapWait0 = 2                   // буквально оттолкнуться — очень короткий контакт
            win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: fallY - SIZE / 2))
            anim += 1
            return
        }
        // приземление: по тикам ИЛИ как только на снижении достигли пола цели
        let reachedFloor = fallVy > 0 && fallY <= leapTY
        if leapTicks >= leapSteps || reachedFloor {
            leapLand(on: dst)
        }
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: fallY - SIZE / 2))
        anim += 1
    }
    // куда уходить гулять: с уклоном «домой» (к экрану с курсором) — сильнее у домоседных настроений
    func chooseWanderDir() -> Bool {                   // true = влево
        let homeBias: Double = { switch mood { case .lazy, .playful: return 0.8; case .curious: return 0.3; default: return 0.55 } }()
        if let cs = cursorScreen(), cs.frame != curScreen().frame, Double.random(in: 0..<1) < homeBias {
            return cs.frame.midX < curScreen().frame.midX
        }
        return Bool.random()
    }

    func bottomY() -> CGFloat { curScreen().frame.minY + SIZE / 2 - FOOT }
    func leftEdge() -> CGFloat  { curScreen().frame.minX + SIZE / 2 }
    func rightEdge() -> CGFloat { curScreen().frame.maxX - SIZE / 2 }
    func randomX() -> CGFloat {
        let s = curScreen()
        return CGFloat.random(in: (s.frame.minX + SIZE)...(s.frame.maxX - SIZE))
    }

    func frame(_ set: String, _ idx: Int, flip: Bool = false) -> NSImage {
        let arr = sets[set] ?? sets["idle"]!
        let (c, r) = arr[idx % arr.count]
        let key = "\(c),\(r)\(flip ? "F" : "")"
        if let cached = cache[key] { return cached }
        let sh = sheet.size.height
        let src = NSRect(x: CGFloat(c) * 32, y: sh - CGFloat(r + 1) * 32, width: 32, height: 32)
        let out = NSImage(size: NSSize(width: SIZE, height: SIZE))
        out.lockFocus()
        NSGraphicsContext.current?.imageInterpolation = .none
        if flip {   // горизонтальное отзеркаливание (для прыжка в другую сторону)
            let t = NSAffineTransform(); t.translateX(by: SIZE, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat()
        }
        sheet.draw(in: NSRect(x: 0, y: 0, width: SIZE, height: SIZE), from: src, operation: .sourceOver, fraction: 1)
        out.unlockFocus()
        cache[key] = out
        return out
    }

    // отрисовать ПРОИЗВОЛЬНУЮ клетку (col,row) — для раскадровки прыжка между мониторами
    func frameCell(_ c: Int, _ r: Int, flip: Bool = false) -> NSImage {
        let key = "\(c),\(r)\(flip ? "F" : "")"
        if let cached = cache[key] { return cached }
        let sh = sheet.size.height
        let src = NSRect(x: CGFloat(c) * 32, y: sh - CGFloat(r + 1) * 32, width: 32, height: 32)
        let out = NSImage(size: NSSize(width: SIZE, height: SIZE))
        out.lockFocus(); NSGraphicsContext.current?.imageInterpolation = .none
        if flip { let t = NSAffineTransform(); t.translateX(by: SIZE, yBy: 0); t.scaleX(by: -1, yBy: 1); t.concat() }
        sheet.draw(in: NSRect(x: 0, y: 0, width: SIZE, height: SIZE), from: src, operation: .sourceOver, fraction: 1)
        out.unlockFocus(); cache[key] = out; return out
    }

    // MARK: перетаскивание
    func dragBegan() {
        dragging = true; clinging = false; flySpin = 0; flyRot = 0; eating = false; eatingRef = nil
        if spacesExperiment { win.collectionBehavior.insert(.canJoinAllSpaces) }   // в руке — следует за курсором на любой спейс
        iv.image = frame("held", 0)
    }
    func dragEnded() {
        dragging = false
        x = win.frame.origin.x + SIZE / 2
        fallY = win.frame.origin.y + SIZE / 2   // откуда падать
        fallVx = max(-42, min(42, iv.throwVel.x * 0.55))      // бросок по параболе (горизонталь шире)
        fallVy = -max(-28, min(28, iv.throwVel.y * 0.55))     // вертикаль скромнее — кот не улетает в космос
        flyHang = false                         // бросили рукой — барахтается лапами
        if let sc = screenAt(NSPoint(x: x, y: fallY)) { homeScreen = sc }   // бросили на другой монитор → он там и живёт
        st = .falling                           // мягко приземлится на лапы (без отскока)
        elog("drag_end", ["vx": Double(fallVx), "vy": Double(fallVy)])
    }

    // Висит на курсоре как настоящий маятник с движущимся подвесом:
    //   θ'' = −(g/L)·sinθ − (a_пивота/L)·cosθ − c·θ'   (полу-неявный Эйлер)
    // Срывается, если поднять выше нижней трети ИЛИ сильно раскачать (улетает по параболе, крутясь).
    func clingStep() {
        let m = NSEvent.mouseLocation
        let s = screenAt(m) ?? curScreen()           // экран, где сейчас курсор
        clingTicks += 1
        if hypot(m.x - clingPrevX, m.y - clingPrevY) < 2 { clingStill += 1 } else { clingStill = 0 }
        clingPrevY = m.y
        let dt = CGFloat(TICK)
        let L = SIZE * 0.5                                   // длина «нити» (курсор → центр кота)
        let g: CGFloat = 800                                // «гравитация» (период ≈ 1.3 c)
        let damp: CGFloat = 3.2                             // вязкость: больше — плавнее и «с весом»

        // ускорение подвеса (курсора): сглаживаем скорость и клипуем пик,
        // иначе дрожь курсора (÷dt дважды) швыряет маятник от малейшего движения
        let rawV = (m.x - clingPrevX) / dt
        let smV = clingPivotV * 0.6 + rawV * 0.4           // low-pass по скорости подвеса
        var pivotA = (smV - clingPivotV) / dt
        clingPivotV = smV; clingPrevX = m.x
        pivotA = max(-1800, min(1800, pivotA))             // ограничить резкий рывок

        let th = Double(clingAngle)
        let acc = -(g / L) * CGFloat(sin(th)) - (pivotA / L) * CGFloat(cos(th)) - damp * clingVel
        clingVel += acc * dt                                // θ' (рад/с)
        clingAngle = max(-1.5, min(1.5, clingAngle + clingVel * dt))

        let cx = m.x + L * CGFloat(sin(Double(clingAngle)))
        let cy = m.y - L * CGFloat(cos(Double(clingAngle)))

        // грип: первые ~1с (10 тиков) держится крепко, дальше слабеет (срывается легче)
        let needVel: CGFloat = clingTicks < 20 ? 9 : 6
        if clingTicks > 10 && abs(clingVel) > needVel {       // сильно раскачали → срывается и летит по параболе
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
        // подняли выше трети экрана → отцепился (после короткой крепкой фазы)
        if clingTicks > 12 && m.y > s.frame.minY + s.frame.height / 3 {
            clinging = false
            x = cx; fallY = cy; fallVx = 0; fallVy = 0; flySpin = 0; flyHang = true
            iv.frameCenterRotation = 0
            st = .falling
            return
        }
        // курсор давно не двигается (~4.5с) → коту надоело, сам спрыгивает
        if clingTicks > 15 && clingStill > 45 {
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
        if leaping { leapStep(); return }   // прыгает между мониторами

        if st == .falling {                 // летит по параболе и мягко садится (без отскока)
            let ground = bottomY()
            let top = curScreen().frame.maxY - SIZE / 2
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
                if hunting { huntSat = min(1.6, huntSat + 0.15) }   // ПРОМАХ охоты: слегка приелся, но интерес остаётся → сразу попробует снова
                flySpin = 0; flyRot = 0; flyHang = false; hunting = false; iv.frameCenterRotation = 0   // приземлился — выпрямился
                if spacesExperiment { win.collectionBehavior.remove(.canJoinAllSpaces) }   // приземлился → снова закреплён за десктопом
                enter(.idle)
                iv.image = frame("idle", 0)
            } else if hunting {
                huntAir += 1
                let m = NSEvent.mouseLocation
                // наклон спрайта по направлению полёта — на всей траектории (включая параболу после промаха)
                let rot = max(-75, min(75, -CGFloat(atan2(Double(fallVx), Double(-fallVy))) * 180 / .pi))
                iv.frameCenterRotation = rot
                // прощающий захват — но не раньше ~0.3с полёта, чтобы был видимый прыжок, а не «прилип» сразу
                if huntAir >= 3, hypot(m.x - x, m.y - fallY) < SIZE * 0.6 {
                    hunting = false; clinging = true
                    huntInterest = 0; huntSat = min(1.6, huntSat + 0.5); huntCool = 25   // ПОЙМАЛ → наигрался немного + пауза
                    if spacesExperiment { win.collectionBehavior.insert(.canJoinAllSpaces); win.orderFrontRegardless() }
                    clingPrevX = m.x; clingPrevY = m.y; clingStill = 0
                    clingPivotV = 0; clingAngle = 0; clingVel = 0; clingTicks = 0
                    iv.frameCenterRotation = 0
                    return
                }
                iv.image = frame("hang", 0)                  // летит к курсору — вытянутые лапы
            } else {
                if flySpin == 0 {
                    if flyHang {   // слетел с курсора — поза висения, носом по скорости
                        iv.frameCenterRotation = max(-75, min(75, -CGFloat(atan2(Double(fallVx), Double(-fallVy))) * 180 / .pi))
                    } else {       // бросили рукой — барахтается, летит ПОПОЙ по траектории (угол скорости + 90°)
                        iv.frameCenterRotation = CGFloat(atan2(Double(-fallVy), Double(fallVx)) * 180 / .pi) + 90
                    }
                }
                iv.image = flyHang ? frame("hang", 0)        // слетел с курсора — поза висения
                                   : frame("fall", anim / 2) // бросили — дрыгает лапками, попой вперёд
            }
            win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: fallY - SIZE / 2))
            anim += 1
            return
        }
        engine.step(self)                   // мозг+поза: Reflex или Utility (физика/драг/падение — общие выше)
    }


    @objc func walkMenu() { startWalkabout() }

    // настроение меняется несколько раз в день (не одно на весь день)
    func rerollMood() {
        let all = Mood.allCases
        var m = all.randomElement() ?? mood
        if all.count > 1 { while m == mood { m = all.randomElement() ?? m } }   // не то же самое подряд
        mood = m
        moodItem?.title = "  Today's mood: \(mood.label)"   // "  " — тот же отступ, что у остальных пунктов (иначе строка «уезжает»)
    }

    // «Позвать котика» — вернуть на видимый экран к курсору, если он ушёл гулять/пропал (противоположность Go for a walk)
    @objc func comeHereMenu() {
        let wasAway = (st == .away) || leaving || goingAway   // был «в туннеле» (ушёл за кадр)
        let calledScreen = cursorScreen() ?? curScreen()      // куда зовут — монитор курсора
        let prevScreen = curScreen()                          // где был до ухода (его домашний монитор)
        goingAway = false; leaving = false; eating = false; eatingRef = nil
        toFood = false; toPlay = false; clinging = false; hunting = false
        flySpin = 0; flyRot = 0; iv.frameCenterRotation = 0; hopOffset = 0
        if wasAway && calledScreen.frame != prevScreen.frame {
            // звали на ДРУГОЙ монитор: сначала выбегает на СВОЙ (где был), потом прыжком на званый
            homeScreen = prevScreen
            comeHereJumpScreen = calledScreen
        } else {
            homeScreen = calledScreen                   // обычно: появляется на мониторе курсора
            comeHereJumpScreen = nil
        }
        let fromLeft = awayLeft                        // выбегает с той стороны, КУДА уходил в away
        x = fromLeft ? (leftEdge() - SIZE) : (rightEdge() + SIZE)   // появляется ЗА кадром (за краем) — пока не видно
        y = bottomY()
        win.setFrameOrigin(NSPoint(x: x - SIZE / 2, y: y - SIZE / 2))
        bringToActiveSpace()                          // окно на нужном десктопе, но кот за кадром
        st = .idle; stTicks = 0; iv.image = frame("idle", 0)
        let runIn = CGFloat.random(in: 150...260)
        let tgt = fromLeft ? min(leftEdge() + runIn, rightEdge()) : max(rightEdge() - runIn, leftEdge())
        let spd = max(6, min(18, runIn / 30))
        // несколько секунд за кадром — тишина, как будто бежит откуда-то, потом показывается и вбегает
        DispatchQueue.main.asyncAfter(deadline: .now() + Double.random(in: 2.0...3.5)) { [weak self] in
            guard let self else { return }
            self.targetX = tgt; self.comeHereSpeed = spd; self.enter(.walk)
        }
        saveState()
    }

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

    // «Check for updates»: нативная строка, клик не закрывает меню — сама строка превращается в серый статус + спиннер
    func makeCheckUpdatesItem() -> NSMenuItem {
        let row = MenuRowView(title: "Check for updates", width: 260, hasCheck: false)
        checkRow = row
        row.onClick = { [weak self, weak row] in
            guard let self, let row else { return }
            row.spinner.startAnimation(nil)
            row.setStatus("Checking…")
            self.checkForUpdates(manual: true) { msg, done in
                row.setStatus(msg)
                if done { row.spinner.stopAnimation(nil) }
            }
        }
        let item = NSMenuItem(); item.view = row
        return item
    }

    // «Auto-update»: нативная галочка (✓ появляется/исчезает), клик не закрывает меню
    func makeAutoUpdateItem() -> NSMenuItem {
        let row = MenuRowView(title: "Auto-update", width: 260, hasCheck: true)
        autoRow = row
        row.setChecked(autoUpdate)
        row.onClick = { [weak self, weak row] in
            guard let self else { return }
            self.autoUpdate.toggle()
            row?.setChecked(self.autoUpdate)
        }
        let item = NSMenuItem(); item.view = row
        return item
    }

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

    // дебаг: вручную запустить конкретное состояние
    @objc func forceState(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        clinging = false; iv.frameCenterRotation = 0; hopOffset = 0
        toFood = false; toPlay = false; goingAway = false; leaving = false; eating = false; eatingRef = nil
        switch key {
        case "sleep":   enter(.sleep)
        case "idle":    enter(.idle)
        case "walk":    targetX = randomX(); enter(.walk)
        case "zoomies": enter(.zoomies)
        case "away":    startWalkabout()
        case "dig":     goingAway = true; awayLeft = Bool.random(); enter(.digging)
        case "hunt":
            let m = NSEvent.mouseLocation
            huntStartX = x
            huntAimX = min(max(m.x, leftEdge()), rightEdge())
            huntAimY = min(max(m.y, y + 40), bottomY() + 320)   // прыжок к курсору (баллистика)
            enter(.hunt)
        case "play":
            let px = min(max(x + 150, leftEdge()), rightEdge())
            let k = makeYarn(x: px, y: bottomY() + 130)
            k.landed = false; k.vy = 0; k.vx = 0
            wakeYarnInterest(k)
        case "fall":
            fallY = bottomY() + 240; fallVx = CGFloat.random(in: -4...4); fallVy = 0
            flySpin = 0; flyHang = true; st = .falling
        case "eat":
            hunger = 0                                   // поел — голод в ноль (просто, для теста)
            if let c = foodTargetX() { toFood = true; toPlay = false; targetX = c; enter(.walk) }  // если есть корм — дойдёт и погрызёт
            else { alert("Нет корма — сначала насыпь (🍚)") }
        case "leapup":   if let s = verticalNeighbor(up: true)  { launchLeap(to: s) } else { alert("Нет монитора сверху") }
        case "leapbounce": if let s = verticalNeighbor(up: true) { launchLeap(to: s, bounce: true) } else { alert("Нет монитора сверху") }
        case "leapdown": if let s = verticalNeighbor(up: false) { launchLeap(to: s) } else { alert("Нет монитора снизу") }
        case "leap":     if let s = anyOtherScreen() { launchLeap(to: s) } else { alert("Других мониторов нет") }
        default: break
        }
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
        dbgState.title   = "  state: \(st.label)"
        dbgEnergy.title  = String(format: "  energy: %.2f", energy)
        dbgBoredom.title = String(format: "  boredom: %.2f", boredom)
        dbgHunger.title  = String(format: "  hunger: %.2f", hunger)
        dbgMood.title    = "  mood: \(mood.label)"
    }

    // дебаг-цифры обновляются ЖИВО, пока меню открыто (таймер в .common — работает и в режиме трекинга меню)
    func menuWillOpen(_ menu: NSMenu) {
        refreshDebug()
        checkRow?.reset()                       // сбросить статус «Check for updates» при открытии
        autoRow?.setChecked(autoUpdate)         // галочка в актуальном состоянии
        dbgMenuTimer?.invalidate()
        guard debugBuild, debug else { return }
        let t = Timer(timeInterval: 0.2, repeats: true) { [weak self] _ in self?.refreshDebug() }
        RunLoop.main.add(t, forMode: .common)
        dbgMenuTimer = t
    }
    func menuDidClose(_ menu: NSMenu) { dbgMenuTimer?.invalidate(); dbgMenuTimer = nil }

    @objc func toggleSpacesExperiment() {
        let v = !UserDefaults.standard.bool(forKey: "neko.spacesExperiment")
        UserDefaults.standard.set(v, forKey: "neko.spacesExperiment")
        spacesItem?.state = v ? .on : .off
        relaunchSelf()                                 // применится сразу — авто-перезапуск (стейт сохраняется)
    }

    func relaunchSelf() {
        saveState()                                    // чтобы кот вернулся туда же и тем же (бесшовно)
        let path = Bundle.main.bundlePath
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/bin/sh")
        p.arguments = ["-c", "sleep 0.4; open \"\(path)\""]
        try? p.run()
        NSApp.terminate(nil)
    }

    @objc func toggleForceDebug() {
        let v = !UserDefaults.standard.bool(forKey: "neko.forceDebug")
        UserDefaults.standard.set(v, forKey: "neko.forceDebug")
        forceDebugItem?.state = v ? .on : .off
        // действует со следующего запуска (дебаг-секция вычисляется на старте); сейчас уже в дебаге
    }

    // CSV-лог реальных состояний (раз в 10с) → ~/Library/Logs/neko-state.csv для аналитики модели нужд
    func logStateSample() {
        guard debugBuild else { return }
        let fm = FileManager.default
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/neko-state.csv")
        let header = "epoch,time,state,energy,boredom,hunger,mood,x\n"
        // ротация по размеру: > 15 МБ → в .csv.1 (одна резервная). Итого ≤ ~30 МБ.
        if let sz = (try? fm.attributesOfItem(atPath: path)[.size]) as? Int, sz > 15_000_000 {
            let bak = path + ".1"; try? fm.removeItem(atPath: bak); try? fm.moveItem(atPath: path, toPath: bak)
        }
        if !fm.fileExists(atPath: path) {
            try? header.write(toFile: path, atomically: true, encoding: .utf8)
        }
        let now = Date()
        let row = String(format: "%.0f,%@,%@,%.3f,%.3f,%.3f,%@,%d\n",
                         now.timeIntervalSince1970, ISO8601DateFormatter().string(from: now),
                         st.label, energy, boredom, hunger, mood.label, Int(x))
        if let h = FileHandle(forWritingAtPath: path) { h.seekToEndOfFile(); h.write(Data(row.utf8)); try? h.close() }
    }

    // структурный лог событий → ~/Library/Logs/neko-events.jsonl: переходы, решения мозга, инпуты из мира
    func elog(_ kind: String, _ data: [String: Any] = [:]) {
        guard debugBuild else { return }
        let fm = FileManager.default
        let path = (NSHomeDirectory() as NSString).appendingPathComponent("Library/Logs/neko-events.jsonl")
        if let sz = (try? fm.attributesOfItem(atPath: path)[.size]) as? Int, sz > 35_000_000 {  // ≤ ~70 МБ с .1
            let bak = path + ".1"; try? fm.removeItem(atPath: bak); try? fm.moveItem(atPath: path, toPath: bak)
        }
        func r(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
        var obj: [String: Any] = ["t": Date().timeIntervalSince1970, "kind": kind, "st": st.label,
                                  "e": r(energy), "b": r(boredom), "h": r(hunger), "mood": mood.label]
        data.forEach { obj[$0] = $1 }
        guard let d = try? JSONSerialization.data(withJSONObject: obj),
              let s = String(data: d, encoding: .utf8) else { return }
        let line = Data((s + "\n").utf8)
        if let fh = FileHandle(forWritingAtPath: path) { fh.seekToEndOfFile(); fh.write(line); try? fh.close() }
        else { try? line.write(to: URL(fileURLWithPath: path)) }
    }

    // лог поведения в дебаг-режиме → /tmp/neko_debug.log (чтобы потом видеть «что было с котом»)
    func dlog(_ msg: String) {
        guard debugBuild, debug else { return }
        let line = String(format: "%@  [%@] e=%.2f b=%.2f h=%.2f x=%d  %@\n",
                          "\(Date())", st.label, energy, boredom, hunger, Int(x), msg)
        let path = "/tmp/neko_debug.log"
        if let h = FileHandle(forWritingAtPath: path) {
            h.seekToEndOfFile(); h.write(Data(line.utf8)); try? h.close()
        } else { try? line.write(toFile: path, atomically: false, encoding: .utf8) }
    }

    // report(message, done): если задан — статус идёт в меню (спиннер/текст), без модальных алертов
    func checkForUpdates(manual: Bool = false, report: ((String, Bool) -> Void)? = nil) {
        func say(_ m: String, done: Bool) {
            DispatchQueue.main.async {
                if let report { report(m, done) } else if manual { self.alert(m) }
            }
        }
        let url = URL(string: "https://api.github.com/repos/\(REPO)/releases/latest")!
        var req = URLRequest(url: url)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        URLSession.shared.dataTask(with: req) { [weak self] data, _, _ in
            guard let self else { return }
            guard let data,
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let tag = json["tag_name"] as? String else {
                say("Couldn't check", done: true); return
            }
            let assets = json["assets"] as? [[String: Any]] ?? []
            let zip = assets.compactMap { $0["browser_download_url"] as? String }.first { $0.hasSuffix(".zip") }
            if self.isNewer(tag), let zip = zip {
                say("Updating to \(tag)…", done: false)
                DispatchQueue.main.async {
                    if self.autoUpdate || report != nil {   // авто-апдейт ИЛИ ручная проверка из меню → ставим сразу
                        self.installUpdate(zip)
                    } else {
                        let a = NSAlert()
                        a.messageText = "A new version \(tag) is available"
                        a.informativeText = "Update Neko now?"
                        a.addButton(withTitle: "Update"); a.addButton(withTitle: "Later")
                        if a.runModal() == .alertFirstButtonReturn { self.installUpdate(zip) }
                    }
                }
            } else {
                say("Latest version (\(VERSION))", done: true)
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
    // отдых за реальное время «вне компа» (ноут спал/закрыт): энергия восстанавливается, как будто кот спал.
    // полный отдых примерно за 2 ч отсутствия; короткие паузы дают чуть-чуть.
    func creditRest(_ seconds: Double) {
        guard seconds > 60 else { return }                 // меньше минуты — не считаем
        let before = energy
        energy = min(1, energy + seconds / 7200)           // 1.0 за ~2 ч
        boredom = min(1, boredom + seconds / 14400)        // и чуть соскучился, пока никого не было
        lastSaveTS = Date().timeIntervalSince1970
        dlog(String(format: "rest +%.2f energy за %.0f мин (вне компа)", energy - before, seconds / 60))
        elog("rest", ["sec": seconds, "gain": energy - before])
    }
    @objc func systemDidWake() {                           // ноут проснулся (крышку открыли) — приложение не выключалось
        creditRest(Date().timeIntervalSince1970 - lastSaveTS)
    }

    // экспериментальный «бродячий» режим Spaces — ФИКСИРУЕТСЯ НА СТАРТЕ (тоггл применяется после перезапуска),
    // иначе живое окно перейдёт в кашу между canJoinAllSpaces и закреплением.

    func bringToActiveSpace() {
        guard spacesExperiment else { win.orderFrontRegardless(); return }   // надёжный режим: окно и так на всех спейсах
        win.collectionBehavior.insert(.canJoinAllSpaces)                     // эксперимент: на миг «на всех», затем снять
        win.orderFrontRegardless()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, !self.clinging, !self.dragging else { return }
            self.win.collectionBehavior.remove(.canJoinAllSpaces)
        }
    }

    @objc func spaceChanged() {                            // ты переключил десктоп → кот чаще приходит за тобой
        guard spacesExperiment else { return }             // надёжный режим: окно и так на всех спейсах, ничего не делаем
        if clinging || dragging {                          // висит/держим: показать на активном
            win.orderFrontRegardless(); elog("space_follow", ["followed": 1, "by": "cursor"]); return
        }
        guard !leaving, st != .away else { return }        // если он сейчас «в туннеле» (ушёл в спейс) — не вытаскиваем
        let follow: Double = { switch mood { case .curious: return 0.55; case .lazy, .playful: return 0.9; default: return 0.8 } }()
        if Double.random(in: 0..<1) < follow {
            bringToActiveSpace()                           // пришёл за тобой на активный десктоп
            elog("space_follow", ["followed": 1])
        } else {
            elog("space_follow", ["followed": 0])          // в этот раз остался на старом десктопе
        }
    }

    func screenNumber(_ s: NSScreen) -> Int {              // стабильный id монитора (переживает перезапуск)
        (s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.intValue ?? 0
    }

    func saveState() {
        let d = UserDefaults.standard
        lastSaveTS = Date().timeIntervalSince1970
        d.set(lastSaveTS, forKey: "neko.savedAt")          // когда сохранили — чтобы начислить отдых при следующем запуске
        d.set(energy, forKey: "neko.energy")
        d.set(boredom, forKey: "neko.boredom")
        d.set(hunger, forKey: "neko.hunger")
        d.set(Double(x), forKey: "neko.x")
        let cs = curScreen()
        d.set(screenNumber(cs), forKey: "neko.screen")            // на каком мониторе был — чтобы вернуться туда же
        d.set(Double(cs.frame.minX), forKey: "neko.screenX")      // + кадр монитора как надёжный фолбэк
        d.set(Double(cs.frame.minY), forKey: "neko.screenY")      // (NSScreenNumber может «плыть» при перезапуске)
        d.set(st.label, forKey: "neko.state")              // чтобы стартовать осмысленно, а не всегда «спать»
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
            // СНАЧАЛА вернуть монитор, на котором был: сперва по стабильному id, иначе по кадру монитора
            // (id иногда «плывёт» при перезапуске — тогда находим тот же монитор по его координатам),
            // и только если монитора реально нет (отключили) — на текущий главный.
            let num = d.object(forKey: "neko.screen") as? Int
            let sx = d.object(forKey: "neko.screenX") as? Double
            let sy = d.object(forKey: "neko.screenY") as? Double
            if let num, num != 0, let sc = NSScreen.screens.first(where: { screenNumber($0) == num }) {
                homeScreen = sc
            } else if let sx, let sy, let sc = NSScreen.screens.first(where: {
                abs($0.frame.minX - CGFloat(sx)) < 2 && abs($0.frame.minY - CGFloat(sy)) < 2 }) {
                homeScreen = sc
            } else {
                homeScreen = NSScreen.main
            }
            if let xx = d.object(forKey: "neko.x") as? Double {        // x уже относительно нужного монитора; не дать спрятаться за краем
                x = min(max(CGFloat(xx), leftEdge()), rightEdge())
            }
            if let ts = d.object(forKey: "neko.savedAt") as? Double {  // отсыпание за время, пока приложение не работало
                creditRest(Date().timeIntervalSince1970 - ts)
            }
            // бесшовно: восстанавливаем стабильное состояние (и координату x — уже выше); переходные → idle
            switch d.string(forKey: "neko.state") {
            case "sleeping": bootState = .sleep
            case "walking":  bootState = .walk
            case "zoomies":  bootState = .zoomies
            default:         bootState = .idle      // digging/away/falling/hunting/playing — безопасно в idle
            }
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
        goingAway = true; toFood = false; awayLeft = chooseWanderDir()
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
        if yarns.count >= 8 { let old = yarns.removeFirst(); old.win.orderOut(nil) }  // лимит окон
        let k = makeYarn(x: min(max(m.x, s.frame.minX + 10), s.frame.maxX - 10), y: m.y)
        k.vx = CGFloat.random(in: -16...16); k.vy = 6; k.landed = false   // придать движение
        wakeYarnInterest(k)   // новый мяч — интерес резко вверх
        elog("yarn_toss", ["count": yarns.count])
    }
    @objc func removeYarnMenu() {            // убираем ВСЕ клубки
        for k in yarns { k.win.orderOut(nil) }
        yarns.removeAll(); toPlay = false; lastPokedYarn = nil
    }

    // ближайший клубок (не схваченный рукой)
    func nearestYarn() -> Yarn? {
        yarns.filter { !$0.dragging }.min(by: { abs($0.x - x) < abs($1.x - x) })
    }
    // предпочитаемый мяч: последний тронутый/новый, иначе ближайший
    func preferredYarn() -> Yarn? {
        if let k = lastPokedYarn, !k.dragging, yarns.contains(where: { $0 === k }) { return k }
        return nearestYarn()
    }
    // резкий всплеск интереса — ТОЛЬКО на новый или тронутый рукой мяч (не на свою же игру)
    func wakeYarnInterest(_ k: Yarn?) {
        playTired = false; playSat = 0; boredom = min(1, boredom + 0.05)
        if let k = k { lastPokedYarn = k }
    }

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
            (rgb(255,90,90),   rgb(200,50,50)),    // красный
            (rgb(90,210,210),  rgb(40,150,150)),   // бирюзовый
            (rgb(185,235,95),  rgb(120,180,40)),   // лаймовый
            (rgb(240,120,230), rgb(190,70,180)),   // маджента
            (rgb(120,200,255), rgb(60,140,210)),   // небесный
            (rgb(255,180,205), rgb(220,120,155)),  // коралловый
            (rgb(160,255,215), rgb(90,200,155)),   // аквамарин
            (rgb(210,190,140), rgb(160,140,90)),   // песочный
            (rgb(150,140,255), rgb(95,80,215)),    // индиго
            (rgb(255,230,130), rgb(220,180,70)),   // золотистый
        ]
        var idx = Int.random(in: 0..<palette.count)
        if idx == lastYarnPalette { idx = (idx + 1) % palette.count }   // не тот же цвет подряд
        lastYarnPalette = idx
        let pick = palette[idx]
        v.ball = pick.0; v.thread = pick.1
        w.contentView = v
        w.setFrameOrigin(NSPoint(x: x - YSIZE / 2, y: y - YSIZE / 2))
        w.orderFrontRegardless()
        let k = Yarn(win: w, view: v, x: x, y: y)
        v.onBegan = { [weak self, weak k] in k?.dragging = true; k?.vx = 0; k?.vy = 0; self?.lastPokedYarn = k }
        v.onMoved = { [weak k] o in
            guard let k = k else { return }
            let nx = o.x + self.YSIZE / 2, ny = o.y + self.YSIZE / 2
            k.vx = max(-40, min(40, nx - k.x)); k.vy = max(-40, min(40, ny - k.y))   // инерция руки
            k.x = nx; k.y = ny
        }
        v.onEnded = { [weak self, weak k] in k?.dragging = false; k?.landed = false; self?.wakeYarnInterest(k) }   // бросок будит интерес к ЭТОМУ мячу
        yarns.append(k)
        return k
    }

    func updateYarn() { for k in yarns where !k.dragging { stepYarn(k) } }

    func stepYarn(_ k: Yarn) {
        let s = screenAt(NSPoint(x: k.x, y: k.y)) ?? NSScreen.main ?? NSScreen.screens[0]   // пол/стены того монитора, где клубок
        let g = s.frame.minY + YSIZE / 2
        k.vy -= 2.0                          // гравитация
        k.x += k.vx; k.y += k.vy
        if k.y <= g {                        // отскок от пола (упругий), потом покой
            k.y = g
            if abs(k.vy) > 2.5 {
                var b = abs(k.vy) * 0.55                       // упругий отскок
                if Double.random(in: 0..<1) < 0.18 { b *= 1.6 }  // иногда скачет сильнее
                k.vy = b
            } else { k.vy = 0 }
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
        let m = NSEvent.mouseLocation
        let s = screenAt(m) ?? NSScreen.main ?? NSScreen.screens[0]   // на тот монитор, где курсор
        let cx = min(max(m.x, s.frame.minX + 8), s.frame.maxX - 8)
        makeKibble(x: cx, y: m.y - 7, maxBites: Int.random(in: 3...4))
        elog("feed", ["x": Double(cx), "kibbles": kibbles.count])
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
        let G: CGFloat = 2.2
        // монитор катышка берём по ЦЕНТРУ (k.y — низ окна, на самом полу = на границе двух экранов → screenAt мигал бы)
        func kscr(_ k: Kibble) -> NSScreen { screenAt(NSPoint(x: k.x, y: k.y + 7)) ?? NSScreen.main ?? NSScreen.screens[0] }
        // устойчивость: приподнятый катышек держится только если подпёрт С ОБЕИХ сторон (ямка),
        // иначе осыпается — в т.ч. прямо когда вытаскиваешь нижний
        for k in kibbles where k.landed && !k.dragging {
            let base = kscr(k).frame.minY                  // пол МОНИТОРА этого катышка (а не основного)
            guard k.y > base + 1 else { continue }
            let below = kibbles.filter { $0 !== k && $0.landed && !$0.dragging && abs($0.x - k.x) < 11 && abs($0.y + 8 - k.y) < 5 }
            let hasLeft  = below.contains { $0.x < k.x - 2 }
            let hasRight = below.contains { $0.x > k.x + 2 }
            if !(hasLeft && hasRight) { k.landed = false }
        }
        var remove: [Kibble] = []
        for k in kibbles where !k.landed && !k.dragging {
            let s = kscr(k)               // монитор, над которым катышек сейчас
            let base = s.frame.minY
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

    // катышек на ТОМ ЖЕ мониторе, что и кот (для вертикально-составленных экранов X совпадает, а монитор — нет)
    func kibbleOnMyScreen(_ k: Kibble) -> Bool {
        screenAt(NSPoint(x: k.x, y: k.y + 7))?.frame == curScreen().frame
    }
    // съесть катышек рядом с котом (в точке остановки)
    func eatNearbyKibble() {
        // начинает грызть верхний катышек кучки (с максимальным y) — только на своём мониторе
        let inRange = kibbles.filter { $0.landed && kibbleOnMyScreen($0) && abs($0.x - x) <= SIZE / 2 }
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
