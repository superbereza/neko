import Cocoa

// Иконка: голова кота (контур замкнут снизу) внутри скруглённого квадрата
// с чёрной пиксельной рамкой на белой плитке. Всё в едином пиксельном масштабе.
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let bgName = CommandLine.arguments.count > 2 ? CommandLine.arguments[2] : "white"
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> NSColor { NSColor(srgbRed: r/255, green: g/255, blue: b/255, alpha: 1) }
let palette: [String: NSColor?] = [
    "white":  NSColor.white,
    "clear":  nil,
    "purple": rgb(124, 92, 240),
    "violet": rgb(150, 110, 250),
    "pink":   rgb(255, 150, 190),
    "blue":   rgb(90, 160, 245),
    "mint":   rgb(120, 220, 180),
    "peach":  rgb(255, 190, 140),
    "dark":   rgb(38, 40, 52),
    "yellow": rgb(255, 210, 90),
]
let fillColor: NSColor? = (palette[bgName] ?? NSColor.white)   // nil → прозрачный
let hasFill = fillColor != nil
// на тёмных фонах кот должен быть белым (он и так белый), рамка — белая для контраста
let darkFill = bgName == "dark" || bgName == "purple" || bgName == "violet" || bgName == "blue"
let borderColor: NSColor = darkFill ? NSColor.white : NSColor.black
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sheet = NSImage(contentsOf: root.appendingPathComponent("assets/oneko.png"))!
let rep = NSBitmapImageRep(data: sheet.tiffRepresentation!)!

// --- 1. достаём голову (кадр 3,3) в пиксельных координатах bitmap (top-left) ---
let yTop = 99, yBot = 113                     // уши … подбородок (без плеч); низ замыкаем сами
let xL = 100, xR = 125
enum Px { case clear, white, black }
func sample(_ x: Int, _ y: Int) -> Px {
    guard x >= 0, y >= 0, x < rep.pixelsWide, y < rep.pixelsHigh, let c = rep.colorAt(x: x, y: y) else { return .clear }
    if c.alphaComponent < 0.4 { return .clear }
    let lum = 0.3*c.redComponent + 0.59*c.greenComponent + 0.11*c.blueComponent
    return lum < 0.5 ? .black : .white
}
let hw = xR - xL, hh = yBot - yTop + 1
var head = Array(repeating: Array(repeating: Px.clear, count: hw), count: hh + 1) // +1 ряд под крышку
for ry in 0..<hh { for rx in 0..<hw { head[ry][rx] = sample(xL + rx, yTop + ry) } }

// --- 2. замыкаем контур снизу: под каждым открытым белым пикселем ставим чёрный ---
for ry in 0..<hh { for rx in 0..<hw where head[ry][rx] == .white {
    if head[ry + 1][rx] == .clear { head[ry + 1][rx] = .black }
}}

// обрезаем по содержимому
var minX = hw, maxX = 0, minY = hh + 1, maxY = 0
for y in 0..<(hh+1) { for x in 0..<hw where head[y][x] != .clear {
    minX = min(minX, x); maxX = max(maxX, x); minY = min(minY, y); maxY = max(maxY, y)
}}
let cw = maxX - minX + 1, ch = maxY - minY + 1

// --- 3. строим плитку: скруглённый квадрат, заливка фоном, пиксельная рамка ---
enum Cell { case empty, fill, border, catWhite, catBlack }
let margin = 5
let side = max(cw, ch) + 2 * margin
let r = 5                                       // радиус скругления (в пикселях)
func insideTile(_ x: Int, _ y: Int) -> Bool {
    // прямоугольник минус скруглённые углы
    let cx = x < r ? r : (x >= side - r ? side - 1 - r : x)
    let cy = y < r ? r : (y >= side - r ? side - 1 - r : y)
    let dx = Double(x - cx), dy = Double(y - cy)
    return dx*dx + dy*dy <= Double(r*r) + 0.5
}
var tile = Array(repeating: Array(repeating: Cell.empty, count: side), count: side)
for y in 0..<side { for x in 0..<side where insideTile(x, y) {
    // рамка = внутренняя клетка, у которой сосед снаружи плитки или это край
    let edge = !insideTile(x-1,y) || !insideTile(x+1,y) || !insideTile(x,y-1) || !insideTile(x,y+1)
    tile[y][x] = edge ? .border : .fill
}}

// кладём голову по центру плитки
let ox = (side - cw) / 2, oy = (side - ch) / 2
for y in 0..<ch { for x in 0..<cw {
    switch head[minY + y][minX + x] {
    case .white: tile[oy + y][ox + x] = .catWhite
    case .black: tile[oy + y][ox + x] = .catBlack
    case .clear: break
    }
}}

// --- 4. рендер в 1024, nearest, прозрачный фон вокруг плитки ---
let S: CGFloat = 1024
let cell = floor(S / CGFloat(side))
let pixSide = cell * CGFloat(side)
let off = (S - pixSide) / 2
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .none
for y in 0..<side { for x in 0..<side {
    let color: NSColor?
    switch tile[y][x] {
    case .empty:    color = nil
    case .fill:     color = hasFill ? fillColor : nil
    case .border:   color = borderColor
    case .catWhite: color = .white
    case .catBlack: color = .black
    }
    guard let c = color else { continue }
    c.setFill()
    // y инвертируем: сетка top-left → холст bottom-left
    NSRect(x: off + CGFloat(x)*cell, y: off + CGFloat(side-1-y)*cell, width: cell, height: cell).fill()
}}
img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rr = NSBitmapImageRep(data: tiff),
      let png = rr.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("Готово: \(outPath)  (плитка \(side)×\(side) px, кот \(cw)×\(ch))")
