import Cocoa

// Иконка тома DMG: пиксельный внешний жёсткий диск (крупные пиксели, плоские оттенки).
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "volicon_1024.png"
func rgb(_ r: Int,_ g: Int,_ b: Int) -> NSColor { NSColor(srgbRed:CGFloat(r)/255,green:CGFloat(g)/255,blue:CGFloat(b)/255,alpha:1) }

let W = 30, H = 30
let bx0 = 3, bx1 = 26, by0 = 2, by1 = 28, r = 3       // корпус пошире + радиус скругления
func insideBody(_ x: Int,_ y: Int) -> Bool {
    if x < bx0 || x > bx1 || y < by0 || y > by1 { return false }
    let cx = x < bx0+r ? bx0+r : (x > bx1-r ? bx1-r : x)
    let cy = y < by0+r ? by0+r : (y > by1-r ? by1-r : y)
    let dx = Double(x-cx), dy = Double(y-cy)
    return dx*dx+dy*dy <= Double(r*r)+0.5
}

var grid = Array(repeating: Array(repeating: NSColor?.none, count: W), count: H) // top-left
for y in 0..<H { for x in 0..<W where insideBody(x,y) {
    let edge = !insideBody(x-1,y) || !insideBody(x+1,y) || !insideBody(x,y-1) || !insideBody(x,y+1)
    if edge { grid[y][x] = .black; continue }
    if y >= 22 {                       // нижняя лицевая панель (безель)
        grid[y][x] = rgb(150,152,162)
    } else if y >= 5 && y <= 8 {       // верхний блик
        grid[y][x] = rgb(240,242,247)
    } else {
        grid[y][x] = rgb(206,208,216)  // корпус
    }
}}
// прорезь на безеле
for x in 7...22 where insideBody(x,24) { grid[24][x] = rgb(105,107,117) }
// розовый LED
if insideBody(23,26) { grid[26][23] = rgb(255,120,170) }
// тонкая тёмная грань над безелем
for x in 0..<W where insideBody(x,21) && grid[21][x] != .black { grid[21][x] = rgb(120,122,132) }

// рендер в 1024, nearest
let S: CGFloat = 1024
let side = max(W, H)
let cell = floor(S / CGFloat(side))
let offX = (S - cell*CGFloat(W)) / 2, offY = (S - cell*CGFloat(H)) / 2
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .none
for y in 0..<H { for x in 0..<W {
    guard let c = grid[y][x] else { continue }
    c.setFill()
    NSRect(x: offX + CGFloat(x)*cell, y: offY + CGFloat(H-1-y)*cell, width: cell, height: cell).fill()
}}
img.unlockFocus()
let png = NSBitmapImageRep(data: img.tiffRepresentation!)!.representation(using:.png,properties:[:])!
try! png.write(to: URL(fileURLWithPath: outPath))
print("Готово: \(outPath)")
