// Run on macOS: swift Tools/generate-pip-video.swift <output.mp4>
// A silent, prerecorded animation for the PiP transport test, not an app heartbeat.
import AppKit
import AVFoundation

let output = URL(fileURLWithPath: CommandLine.arguments[1])
let writer = try AVAssetWriter(outputURL: output, fileType: .mp4)
let input = AVAssetWriterInput(mediaType: .video, outputSettings: [
    AVVideoCodecKey: AVVideoCodecType.h264,
    AVVideoWidthKey: 640, AVVideoHeightKey: 360
])
let adaptor = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: input,
    sourcePixelBufferAttributes: [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32ARGB,
                                 kCVPixelBufferWidthKey as String: 640,
                                 kCVPixelBufferHeightKey as String: 360,
                                 kCVPixelBufferCGImageCompatibilityKey as String: true,
                                 kCVPixelBufferCGBitmapContextCompatibilityKey as String: true])
writer.add(input)
guard writer.startWriting() else { fatalError("Start failed: \(String(describing: writer.error))") }
writer.startSession(atSourceTime: .zero)
for frame in 0..<120 {
    while !input.isReadyForMoreMediaData {
        guard writer.status == .writing else { fatalError("Writer failed: \(String(describing: writer.error))") }
        Thread.sleep(forTimeInterval: 0.01)
    }
    var storage: CVPixelBuffer?
    guard CVPixelBufferPoolCreatePixelBuffer(nil, adaptor.pixelBufferPool!, &storage) == kCVReturnSuccess,
          let buffer = storage else { fatalError("Pixel buffer allocation failed") }
    CVPixelBufferLockBaseAddress(buffer, [])
    let context = CGContext(data: CVPixelBufferGetBaseAddress(buffer), width: 640, height: 360,
        bitsPerComponent: 8, bytesPerRow: CVPixelBufferGetBytesPerRow(buffer),
        space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue)!
    context.setFillColor(CGColor(red: 0.03, green: 0.10, blue: 0.18, alpha: 1))
    context.fill(CGRect(x: 0, y: 0, width: 640, height: 360))
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
    for (text, y, size) in [("SKYBOX PiP TEST", 235.0, 44.0),
                           ("Prerecorded clip • \(frame / 2)s", 165.0, 28.0),
                           ("Check Event log for live heartbeats", 90.0, 23.0)] {
        (text as NSString).draw(at: NSPoint(x: 35, y: y), withAttributes: [
            .font: NSFont.systemFont(ofSize: size), .foregroundColor: NSColor.white])
    }
    NSGraphicsContext.restoreGraphicsState()
    context.setFillColor(CGColor(red: 0.2, green: 0.9, blue: 0.6, alpha: 1))
    context.fill(CGRect(x: 35, y: 35, width: Double(frame + 1) / 120 * 570, height: 12))
    CVPixelBufferUnlockBaseAddress(buffer, [])
    guard adaptor.append(buffer, withPresentationTime: CMTime(value: Int64(frame), timescale: 2)) else {
        fatalError("Frame write failed: \(String(describing: writer.error))")
    }
}
writer.endSession(atSourceTime: CMTime(seconds: 60, preferredTimescale: 2))
input.markAsFinished()
let completion = DispatchSemaphore(value: 0)
writer.finishWriting { completion.signal() }
completion.wait()
guard writer.status == .completed else { fatalError("Finish failed: \(String(describing: writer.error))") }
print("Wrote \(output.path)")
