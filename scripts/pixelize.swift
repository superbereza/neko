import Cocoa

// Превращает «гладкую» картинку кота (из Nano Banana и т.п.) в кадр oneko-стиля:
// прозрачный фон, белая шерсть, чёрный 1px контур + тёмные детали (глаза/нос).
// Использование: pixelize.swift <вход.png> <выход.png> [grid=32] [align=bottom|center]
let A = CommandLine.arguments
guard A.count >= 3 else { print("pixelize <in> <out> [grid] [align]"); exit(1) }
let inPath = A[1], outPath = A[2]
let grid = A.count > 3 ? Int(A[3]) ?? 32 : 32
let align = A.count > 4 ? A[4] : "bottom"

guard let img = NSImage(contentsOfFile: inPath), let rep = NSBitmapImageRep(data: img.tiffRepresentation!) else {
    print("не открыть \(inPath)"); exit(1)
}
let PW = rep.pixelsWide, PH = rep.pixelsHigh
func at(_ x: Int,_ y: Int) -> (r: Double,g: Double,b: Double,a: Double) {
    guard let c = rep.colorAt(x: x, y: y)?.usingColorSpace(.sRGB) else { return (0,0,0,0) }
    return (c.redComponent, c.greenComponent, c.blueComponent, c.alphaComponent)
}

// 1. фон: если есть альфа — по альфе; иначе по цвету углов (хромакей)
var hasAlpha = false
for x in stride(from: 0, to: PW, by: max(1,PW/40)) { if at(x,0).a < 0.95 || at(x,PH-1).a < 0.95 { hasAlpha = true; break } }
let corners = [at(0,0), at(PW-1,0), at(0,PH-1), at(PW-1,PH-1)]
let bg = (corners.reduce(0){$0+$1.r}/4, corners.reduce(0){$0+$1.g}/4, corners.reduce(0){$0+$1.b}/4)
func isFg(_ x: Int,_ y: Int) -> Bool {
    let p = at(x,y)
    if hasAlpha { return p.a > 0.5 }
    let d = abs(p.r-bg.0)+abs(p.g-bg.1)+abs(p.b-bg.2)
    return d > 0.25
}

// 2. bbox переднего плана
var minX = PW, maxX = 0, minY = PH, maxY = 0
for y in 0..<PH { for x in 0..<PW where isFg(x,y) {
    minX=min(minX,x);maxX=max(maxX,x);minY=min(minY,y);maxY=max(maxY,y) } }
guard maxX >= minX else { print("пустая картинка"); exit(1) }
let bw = maxX-minX+1, bh = maxY-minY+1

// 3. ужать в сетку: масштаб так, чтобы влезть в (grid-2) с полем 1px
let inner = grid - 2
let scale = Double(inner) / Double(max(bw, bh))
let gw = max(1, Int((Double(bw)*scale).rounded())), gh = max(1, Int((Double(bh)*scale).rounded()))
let ox = (grid - gw)/2
let oy = align == "bottom" ? (grid - 1 - gh) : (grid - gh)/2   // лапки книзу

// 0 пусто, 1 белый, 2 чёрный
var g = Array(repeating: Array(repeating: 0, count: grid), count: grid)
for cy in 0..<gh { for cx in 0..<gw {
    // область исходника под клетку
    let sx0 = minX + Int(Double(cx)/scale), sx1 = minX + Int(Double(cx+1)/scale)
    let sy0 = minY + Int(Double(cy)/scale), sy1 = minY + Int(Double(cy+1)/scale)
    var n = 0, fg = 0, lum = 0.0
    for sy in sy0..<max(sy0+1,sy1) { for sx in sx0..<max(sx0+1,sx1) where sx<PW && sy<PH {
        n += 1; if isFg(sx,sy) { fg += 1; let p = at(sx,sy); lum += 0.3*p.r+0.59*p.g+0.11*p.b }
    }}
    if n == 0 || Double(fg)/Double(n) < 0.45 { continue }       // фон
    let avg = lum/Double(fg)
    g[oy+cy][ox+cx] = avg < 0.5 ? 2 : 1                          // тёмное→контур, светлое→шерсть
}}

// 4. принудительно достроить чистый контур по границе силуэта
var out = g
for y in 0..<grid { for x in 0..<grid where g[y][x] == 1 {
    for (dx,dy) in [(-1,0),(1,0),(0,-1),(0,1)] {
        let nx=x+dx, ny=y+dy
        if nx<0||ny<0||nx>=grid||ny>=grid || g[ny][nx]==0 { out[y][x] = 2; break }
    }
}}
g = out

// 5. рендер: native grid + увеличенное превью
func write(_ side: Int,_ path: String) {
    let cell = CGFloat(side)/CGFloat(grid)
    let im = NSImage(size: NSSize(width: side, height: side))
    im.lockFocus(); NSGraphicsContext.current?.imageInterpolation = .none
    for y in 0..<grid { for x in 0..<grid {
        let v = g[y][x]; if v==0 { continue }
        (v==2 ? NSColor.black : NSColor.white).setFill()
        NSRect(x: CGFloat(x)*cell, y: CGFloat(grid-1-y)*cell, width: cell, height: cell).fill()
    }}
    im.unlockFocus()
    let png = NSBitmapImageRep(data: im.tiffRepresentation!)!.representation(using:.png,properties:[:])!
    try! png.write(to: URL(fileURLWithPath: path))
}
write(grid, outPath)
write(512, outPath.replacingOccurrences(of: ".png", with: "_preview.png"))
print("Готово: \(outPath)  (fg bbox \(bw)×\(bh) → grid \(gw)×\(gh), alpha=\(hasAlpha))")
