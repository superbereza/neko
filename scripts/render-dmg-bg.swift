import Cocoa

// Фон окна DMG в стиле кота: белый фон, чёрный ПИКСЕЛЬНЫЙ текст и стрелка.
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "dmgbg.png"
let W: CGFloat = 600, H: CGFloat = 400

// пиксельный текст: рендерим мелко без сглаживания, масштабируем nearest
func pixelText(_ s: String, _ size: CGFloat, _ scale: CGFloat) -> NSImage {
    let attrs: [NSAttributedString.Key: Any] = [
        .font: NSFont.boldSystemFont(ofSize: size), .foregroundColor: NSColor.black]
    let str = NSAttributedString(string: s, attributes: attrs)
    let sz = str.size()
    let small = NSImage(size: NSSize(width: ceil(sz.width), height: ceil(sz.height)))
    small.lockFocus()
    NSGraphicsContext.current?.shouldAntialias = false      // 1-битный текст → чёткие пиксели
    str.draw(at: .zero)
    small.unlockFocus()
    let big = NSImage(size: NSSize(width: ceil(sz.width) * scale, height: ceil(sz.height) * scale))
    big.lockFocus()
    NSGraphicsContext.current?.imageInterpolation = .none
    small.draw(in: NSRect(origin: .zero, size: big.size))
    big.unlockFocus()
    return big
}

let img = NSImage(size: NSSize(width: W, height: H))
img.lockFocus()
NSColor.white.setFill(); NSRect(x: 0, y: 0, width: W, height: H).fill()

// заголовок «Neko»
let title = pixelText("Neko", 11, 6)
title.draw(at: NSPoint(x: (W - title.size.width) / 2, y: H - 40 - title.size.height),
           from: .zero, operation: .sourceOver, fraction: 1)

// подпись снизу
let sub = pixelText("drag the cat into Applications", 7, 3)
sub.draw(at: NSPoint(x: (W - sub.size.width) / 2, y: 36),
         from: .zero, operation: .sourceOver, fraction: 1)

// пиксельная стрелка по центру (между иконками) — из квадратов
let cy = H / 2 - 10
let px: CGFloat = 7
func blk(_ gx: Int, _ gy: Int) {   // клетка относительно центра
    NSRect(x: W / 2 + CGFloat(gx) * px, y: cy + CGFloat(gy) * px, width: px, height: px).fill()
}
NSColor.black.setFill()
for gx in -6...3 { blk(gx, 0) }                 // древко
for k in 1...3 { blk(3 - k, k); blk(3 - k, -k) } // наконечник

img.unlockFocus()
guard let tiff = img.tiffRepresentation, let r = NSBitmapImageRep(data: tiff),
      let png = r.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("Готово: \(outPath)")
