import AppKit
// Usage: render <in.svg> <pixels> <out.png>: draws the SVG onto a transparent sRGB canvas of that
// size, so the output does not depend on this Mac's display profile. render.sh runs it for every slot.
func fail(_ message: String) -> Never {
    FileHandle.standardError.write("render: \(message)\n".data(using: .utf8)!)
    exit(1)
}
let args = CommandLine.arguments
guard args.count == 4 else { fail("usage: render <in.svg> <pixels> <out.png>") }
guard let pixels = Int(args[2]), pixels > 0 else { fail("\(args[2]) is not a pixel size") }
guard let image = NSImage(contentsOfFile: args[1]) else { fail("cannot load \(args[1])") }
guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                 samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                 bytesPerRow: 0, bitsPerPixel: 0)?.retagging(with: .sRGB),
      let context = NSGraphicsContext(bitmapImageRep: rep) else { fail("cannot create a \(pixels) px canvas") }
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = context
context.imageInterpolation = .high
// A new rep starts fully transparent, so only the art is drawn.
image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels))
NSGraphicsContext.restoreGraphicsState()
guard let png = rep.representation(using: .png, properties: [:]) else { fail("cannot encode \(args[3])") }
do { try png.write(to: URL(fileURLWithPath: args[3])) } catch { fail("cannot write \(args[3]): \(error.localizedDescription)") }
