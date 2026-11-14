import AppKit
// Renders the SF Symbols used in the menu to docs/menu-icons for the README.
// Usage: swift Scripts/render-menu-icons.swift docs/menu-icons
let out = CommandLine.arguments[1]
let names = ["pin","mic","exclamationmark.triangle","waveform","speaker.wave.2","sun.max","cup.and.saucer","moon.zzz","timer","infinity","display","powerplug","power","rectangle.portrait.and.arrow.right","wrench.and.screwdriver"]
let canvas: CGFloat = 40
for n in names {
    let cfg = NSImage.SymbolConfiguration(pointSize: 28, weight: .regular)
    let sym = NSImage(systemSymbolName: n, accessibilityDescription: nil)!.withSymbolConfiguration(cfg)!
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(canvas), pixelsHigh: Int(canvas), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    let s = sym.size
    let scale = min(canvas / s.width, canvas / s.height, 1)
    let w = s.width * scale, h = s.height * scale
    sym.draw(in: NSRect(x: (canvas - w) / 2, y: (canvas - h) / 2, width: w, height: h))
    NSColor(srgbRed: 0.53, green: 0.55, blue: 0.60, alpha: 1).setFill()
    NSRect(x: 0, y: 0, width: canvas, height: canvas).fill(using: .sourceAtop)
    NSGraphicsContext.restoreGraphicsState()
    try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: "\(out)/\(n).png"))
}
