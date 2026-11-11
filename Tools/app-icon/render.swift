import AppKit
// Usage: swift render.swift <in.svg> <pixels> <out.png>: draws the SVG onto a transparent canvas
// of that size. Tools/app-icon/render.sh runs it for every app icon slot.
let args = CommandLine.arguments
guard args.count == 4, let image = NSImage(contentsOfFile: args[1]), let pixels = Int(args[2]) else {
    FileHandle.standardError.write("cannot load \(args.dropFirst().first ?? "")\n".data(using: .utf8)!); exit(1)
}
let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                           samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                           bytesPerRow: 0, bitsPerPixel: 0)!
rep.size = NSSize(width: pixels, height: pixels)
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
NSGraphicsContext.current?.imageInterpolation = .high
NSColor.clear.set(); NSRect(x: 0, y: 0, width: pixels, height: pixels).fill()
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[3]))
