import Cocoa

// Пиксель-арт «котик висит за шкирку». B=чёрный, W=белый, .=прозрачно.
let art = [
    "......BB........",
    ".....B..B.......",   // рука держит за шкирку (защип)
    "....BB..BB......",
    "...B.B..B.B.....",   // ушки
    "...B.WBWWB.B....",
    "..B.WWWWWWWB....",   // голова
    "..B.WBWWWBW.B...",   // глазки
    "..B.WWWWWWW.B...",
    "..B.WW.^^.WW.B..",   // нос/рот (^ как .)
    "...B.WWWWWW.B...",
    "...BWWWWWWWWB...",
    "..BWWWWWWWWWWB..",   // тело
    "..BWWWWWWWWWWB..",
    "..BWWWWWWWWWWB..",
    "...BWWWWWWWWB...",
    "...B.WWWWWW.B...",
    "..B.B.B..B.B.B..",   // лапки вниз
    "..BW.B....B.WB..",
    "...BB......BB...",
]

let CELL: CGFloat = 12
let cols = art.map { $0.count }.max() ?? 16
let rows = art.count
let W = CGFloat(cols) * CELL, H = CGFloat(rows) * CELL

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
for (ri, row) in art.enumerated() {
    for (ci, ch) in row.enumerated() {
        let color: NSColor?
        switch ch {
        case "B": color = .black
        case "W": color = .white
        default:  color = nil
        }
        guard let c = color else { continue }
        c.setFill()
        // y сверху вниз → переворачиваем
        let rect = NSRect(x: CGFloat(ci) * CELL, y: H - CGFloat(ri + 1) * CELL, width: CELL, height: CELL)
        rect.fill()
    }
}
img.unlockFocus()

let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "held.png"
if let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
   let png = rep.representation(using: .png, properties: [:]) {
    try! png.write(to: URL(fileURLWithPath: out))
    print("ok: \(out)")
}
