import Cocoa

// Иконка: голова кота из спрайта (пиксельный контур, прозрачный фон), по центру с равными полями.
let outPath = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "icon_1024.png"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let sheet = NSImage(contentsOf: root.appendingPathComponent("assets/oneko.png"))!

// область головы в кадре (3,3), симметрична относительно центра ячейки (x=112): 100..124
let src = NSRect(x: 100, y: 13, width: 24, height: 18)

let S: CGFloat = 1024
let pad = S * 0.12
let box = S - 2 * pad
let scale = min(box / src.width, box / src.height)
let w = src.width * scale, h = src.height * scale
let dst = NSRect(x: (S - w) / 2, y: (S - h) / 2, width: w, height: h)   // равные поля

let img = NSImage(size: NSSize(width: S, height: S))
img.lockFocus()
NSGraphicsContext.current?.imageInterpolation = .none   // пиксельный контур
sheet.draw(in: dst, from: src, operation: .sourceOver, fraction: 1)
img.unlockFocus()

FileHandle.standardError.write(Data("margins L/R=\((S-w)/2)  T/B=\((S-h)/2)\n".utf8))
guard let tiff = img.tiffRepresentation, let r = NSBitmapImageRep(data: tiff),
      let png = r.representation(using: .png, properties: [:]) else { exit(1) }
try! png.write(to: URL(fileURLWithPath: outPath))
print("Готово: \(outPath)")
