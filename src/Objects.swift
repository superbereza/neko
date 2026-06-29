import Cocoa

final class NekoWindow: NSWindow {
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }
}

// Кот: ловит перетаскивание
final class NekoView: NSImageView {
    var began: (() -> Void)?
    var moved: ((CGPoint) -> Void)?
    var ended: (() -> Void)?
    var throwVel = CGPoint.zero       // скорость броска (для параболы при отпускании)
    private var lastMouse = NSPoint.zero
    override func mouseDown(with e: NSEvent) {
        lastMouse = NSEvent.mouseLocation
        throwVel = .zero
        began?()
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        throwVel = CGPoint(x: m.x - lastMouse.x, y: m.y - lastMouse.y)   // мгновенная скорость руки
        lastMouse = m
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

// Клубок — пиксельный мячик в полосочку (цвет задаётся при создании); катается, кидается.
// Рисуется процедурным кругом с пикселем = SCALE (как у кота), а не растянутой иконкой.
final class YarnView: NSView {
    static let grid = 14                                                  // клеток в диаметре
    var ball = NSColor(srgbRed: 1, green: 0.47, blue: 0.66, alpha: 1)     // основной цвет
    var thread = NSColor(srgbRed: 0.82, green: 0.31, blue: 0.51, alpha: 1) // нитки-полоски
    var onBegan: (() -> Void)?, onMoved: ((CGPoint) -> Void)?, onEnded: (() -> Void)?
    private var startMouse = NSPoint.zero, startOrigin = NSPoint.zero
    override func mouseDown(with e: NSEvent) {
        startMouse = NSEvent.mouseLocation; startOrigin = window?.frame.origin ?? .zero; onBegan?()
    }
    override func mouseDragged(with e: NSEvent) {
        let m = NSEvent.mouseLocation
        let o = NSPoint(x: startOrigin.x + (m.x - startMouse.x), y: startOrigin.y + (m.y - startMouse.y))
        window?.setFrameOrigin(o); onMoved?(o)
    }
    override func mouseUp(with e: NSEvent) { onEnded?() }
    override func draw(_ r: NSRect) {
        let n = YarnView.grid
        let cell = bounds.width / CGFloat(n)        // = SCALE, пиксель как у кота
        let c = (Double(n) - 1) / 2.0
        let rad = Double(n) / 2.0 - 0.5
        func inside(_ ci: Int, _ ri: Int) -> Bool {
            let dx = Double(ci) - c, dy = Double(ri) - c
            return (dx * dx + dy * dy).squareRoot() <= rad
        }
        for ri in 0..<n { for ci in 0..<n where inside(ci, ri) {
            // контур = ровно граничная клетка (1 клетка = 2px, как у кота)
            let edge = !inside(ci - 1, ri) || !inside(ci + 1, ri) || !inside(ci, ri - 1) || !inside(ci, ri + 1)
            let col: NSColor = edge ? .black : ((ri + ci) % 3 == 0 ? thread : ball)  // диагональные полоски
            col.setFill()
            NSRect(x: CGFloat(ci) * cell, y: CGFloat(ri) * cell, width: cell, height: cell).fill()
        }}
    }
}

final class Yarn {
    let win: NSWindow; let view: YarnView
    var x: CGFloat, y: CGFloat
    var vx: CGFloat = 0, vy: CGFloat = 0
    var landed = false, dragging = false
    var angle: Double = 0      // угол качения (вращение спрайта)
    init(win: NSWindow, view: YarnView, x: CGFloat, y: CGFloat) {
        self.win = win; self.view = view; self.x = x; self.y = y
    }
}

// Нативно выглядящая строка меню (view-based), но клик НЕ закрывает меню.
// Родная галочка слева, спиннер справа; подсветка при наведении — как в системном меню.
final class MenuRowView: NSView {
    private let titleLabel = NSTextField(labelWithString: "")
    private let check = NSImageView()
    let spinner = NSProgressIndicator()
    var onClick: (() -> Void)?
    private var hot = false
    private let hasCheck: Bool
    private let baseTitle: String
    private var grayed = false

    init(title: String, width: CGFloat, hasCheck: Bool) {
        self.hasCheck = hasCheck; self.baseTitle = title
        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 22))
        titleLabel.font = NSFont.menuFont(ofSize: 0)
        titleLabel.stringValue = title
        titleLabel.lineBreakMode = .byTruncatingTail
        titleLabel.frame = NSRect(x: 21, y: 3, width: width - 46, height: 16)
        addSubview(titleLabel)
        if hasCheck {
            check.image = NSImage(named: NSImage.menuOnStateTemplateName)
            check.frame = NSRect(x: 6, y: 5, width: 12, height: 12)
            check.isHidden = true
            addSubview(check)
        }
        spinner.style = .spinning; spinner.controlSize = .small
        spinner.isDisplayedWhenStopped = false; spinner.usesThreadedAnimation = true
        spinner.frame = NSRect(x: width - 24, y: 3, width: 16, height: 16)
        addSubview(spinner)
    }
    required init?(coder: NSCoder) { fatalError() }

    func setChecked(_ on: Bool) { check.isHidden = !on; check.contentTintColor = hot ? .selectedMenuItemTextColor : .labelColor }
    func setStatus(_ s: String) { grayed = true; titleLabel.stringValue = s; recolor() }
    func reset() { grayed = false; titleLabel.stringValue = baseTitle; spinner.stopAnimation(nil); recolor() }

    private func recolor() {
        if grayed { titleLabel.textColor = hot ? .selectedMenuItemTextColor : .secondaryLabelColor }
        else      { titleLabel.textColor = hot ? .selectedMenuItemTextColor : .labelColor }
        if hasCheck { check.contentTintColor = hot ? .selectedMenuItemTextColor : .labelColor }
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach { removeTrackingArea($0) }
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect], owner: self))
    }
    override func mouseEntered(with e: NSEvent) { hot = true; recolor(); needsDisplay = true }
    override func mouseExited(with e: NSEvent)  { hot = false; recolor(); needsDisplay = true }
    override func mouseUp(with e: NSEvent)      { if bounds.contains(convert(e.locationInWindow, from: nil)) { onClick?() } }
    override func draw(_ r: NSRect) {
        if hot { NSColor.selectedContentBackgroundColor.setFill(); bounds.fill() }
        super.draw(r)
    }
}
