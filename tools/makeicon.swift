// Generates AppIcon.png (1024x1024) — a little Game Boy with a T3d screen
import Cocoa

let size: CGFloat = 1024
let image = NSImage(size: NSSize(width: size, height: size))
image.lockFocus()

// Rounded-square background, deep slate
let bgRect = NSRect(x: 64, y: 64, width: 896, height: 896)
let bg = NSBezierPath(roundedRect: bgRect, xRadius: 200, yRadius: 200)
let bgGradient = NSGradient(colors: [
    NSColor(srgbRed: 0.16, green: 0.17, blue: 0.24, alpha: 1),
    NSColor(srgbRed: 0.10, green: 0.11, blue: 0.16, alpha: 1),
])!
bgGradient.draw(in: bg, angle: -90)

// Game Boy shell
let shellRect = NSRect(x: 272, y: 144, width: 480, height: 736)
let shell = NSBezierPath(roundedRect: shellRect, xRadius: 60, yRadius: 60)
NSColor(srgbRed: 0.78, green: 0.78, blue: 0.74, alpha: 1).setFill()
shell.fill()

// Screen bezel
let bezelRect = NSRect(x: 312, y: 520, width: 400, height: 312)
let bezel = NSBezierPath(roundedRect: bezelRect, xRadius: 28, yRadius: 28)
NSColor(srgbRed: 0.28, green: 0.30, blue: 0.36, alpha: 1).setFill()
bezel.fill()

// Screen (DMG green)
let screenRect = NSRect(x: 352, y: 552, width: 320, height: 248)
NSColor(srgbRed: 0.61, green: 0.74, blue: 0.06, alpha: 1).setFill()
NSBezierPath(roundedRect: screenRect, xRadius: 8, yRadius: 8).fill()

// "T3d" on the screen
let screenText = "T3d" as NSString
let screenAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 120, weight: .heavy),
    .foregroundColor: NSColor(srgbRed: 0.06, green: 0.22, blue: 0.06, alpha: 1),
]
let stSize = screenText.size(withAttributes: screenAttrs)
screenText.draw(at: NSPoint(x: screenRect.midX - stSize.width / 2,
                            y: screenRect.midY - stSize.height / 2),
                withAttributes: screenAttrs)

// D-pad
NSColor(srgbRed: 0.20, green: 0.21, blue: 0.25, alpha: 1).setFill()
NSBezierPath(roundedRect: NSRect(x: 332, y: 320, width: 130, height: 44), xRadius: 10, yRadius: 10).fill()
NSBezierPath(roundedRect: NSRect(x: 375, y: 277, width: 44, height: 130), xRadius: 10, yRadius: 10).fill()

// A / B buttons
NSColor(srgbRed: 0.55, green: 0.13, blue: 0.30, alpha: 1).setFill()
NSBezierPath(ovalIn: NSRect(x: 560, y: 330, width: 76, height: 76)).fill()
NSBezierPath(ovalIn: NSRect(x: 640, y: 370, width: 76, height: 76)).fill()

// Falling tetromino on the shell, below the screen
NSColor(srgbRed: 0.24, green: 0.45, blue: 0.22, alpha: 1).setFill()
for block in [(0, 0), (1, 0), (2, 0), (1, 1)] {
    NSBezierPath(roundedRect: NSRect(x: 462 + CGFloat(block.0) * 34, y: 196 + CGFloat(block.1) * 34,
                                     width: 30, height: 30), xRadius: 4, yRadius: 4).fill()
}

// "T3d BOY" wordmark
let mark = "T3d BOY" as NSString
let markAttrs: [NSAttributedString.Key: Any] = [
    .font: NSFont.systemFont(ofSize: 64, weight: .heavy),
    .foregroundColor: NSColor(srgbRed: 0.90, green: 0.91, blue: 0.95, alpha: 1),
]
let mSize = mark.size(withAttributes: markAttrs)
mark.draw(at: NSPoint(x: size / 2 - mSize.width / 2, y: 88), withAttributes: markAttrs)

image.unlockFocus()

guard let tiff = image.tiffRepresentation,
      let rep = NSBitmapImageRep(data: tiff),
      let png = rep.representation(using: .png, properties: [:]) else {
    fatalError("PNG encode failed")
}
let out = CommandLine.arguments.count > 1 ? CommandLine.arguments[1] : "AppIcon.png"
try! png.write(to: URL(fileURLWithPath: out))
print("Wrote \(out)")
