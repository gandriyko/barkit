import AppKit

let args = CommandLine.arguments
let src = URL(fileURLWithPath: args[1])
let out = URL(fileURLWithPath: args[2])
let size = Int(args[3])!

guard let image = NSImage(contentsOf: src) else { fatalError("cannot load svg") }
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size,
                                 bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                 colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0) else { fatalError() }
rep.size = NSSize(width: size, height: size)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
// NSImage's SVG renderer ignores <filter>, so the outer drop shadow is drawn here.
let scale = CGFloat(size) / 1024
let shadow = NSShadow()
shadow.shadowOffset = NSSize(width: 0, height: -16 * scale)
shadow.shadowBlurRadius = 36 * scale
shadow.shadowColor = NSColor.black.withAlphaComponent(0.28)
shadow.set()
image.draw(in: NSRect(x: 0, y: 0, width: size, height: size))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: out)
