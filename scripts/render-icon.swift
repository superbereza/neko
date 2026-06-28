import Cocoa

// Иконка приложения: голова кота из спрайта (белая, чёрный пиксельный контур), фон прозрачный.
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sheet = NSImage(contentsOf: root.appendingPathComponent("assets/oneko.png"))!

let S: CGFloat = 1024
let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .none   // чёткие пиксели

// область головы в oneko.png (кадр 3,3): уши + морда, центрирована по середине ячейки (x=112)
let src = NSRect(x: 100, y: 13, width: 24, height: 18)
// вписываем с полями, сохраняя пропорции
let pad = S * 0.1
let box = S - 2 * pad
let scale = min(box / src.width, box / src.height)
let w = src.width * scale, h = src.height * scale
let dst = NSRect(x: (S - w) / 2, y: (S - h) / 2, width: w, height: h)
sheet.draw(in: dst, from: src, operation: .sourceOver, fraction: 1)

img.unlockFocus()
guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write(Data("render failed\n".utf8)); exit(1)
}
try! png.write(to: URL(fileURLWithPath: outPath))
print("Готово: \(outPath)")
