import AppKit
import Combine
import CoreImage
import ScreenCaptureKit

/// Main-queue lifecycle with a serial queue for frame conversion and file writes.
final class VideoProbe: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    enum Phase { case idle, choosing, starting, capturing, stopping }
    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Choose a window or display to test native video capture."
    @Published private(set) var preview: NSImage?
    @Published private(set) var frameCount = 0
    @Published private(set) var lastFrameAt: Date?
    @Published private(set) var folder: URL?
    private let picker = SCContentSharingPicker.shared
    private let frameQueue = DispatchQueue(label: "com.nohandsstack.skybox.video-probe")
    private let context = CIContext()
    private var stream: SCStream?
    private var stopTimer: Timer?
    // The following state is only accessed on frameQueue.
    private var acceptedStream: SCStream?
    private var frameFolder: URL?
    private var savedFirst = false

    override init() {
        super.init()
        picker.add(self)
    }

    deinit { picker.remove(self) }

    func choose(display: Bool) {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .idle else { return }
        phase = .choosing
        preview = nil
        frameCount = 0
        lastFrameAt = nil
        status = "Choose content in the macOS sharing picker."
        var configuration = SCContentSharingPickerConfiguration()
        configuration.allowedPickerModes = [.singleWindow, .singleDisplay]
        configuration.allowsChangingSelectedContent = false
        picker.defaultConfiguration = configuration
        picker.isActive = true
        picker.present(using: display ? .display : .window)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        stopTimer?.invalidate()
        stopTimer = nil
        picker.isActive = false
        if phase == .choosing {
            phase = .idle
            status = "Selection canceled."
            return
        }
        guard let stream, phase != .stopping else { return }
        phase = .stopping
        frameQueue.sync { acceptedStream = nil }
        stream.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.stream === stream else { return }
                self.stream = nil
                self.phase = .idle
                self.status = error.map { "Stop failed: \($0.localizedDescription)" } ?? "Stopped. Preview is the last captured frame."
                self.saveStatus()
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            self.phase = .idle
            self.picker.isActive = false
            self.status = "Selection canceled."
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            self.phase = .idle
            self.picker.isActive = false
            self.status = "Picker failed: \(error.localizedDescription)"
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            do {
                let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                    .appendingPathComponent("SkyboxAudioProbe/video-\(UUID().uuidString)", isDirectory: true)
                try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                self.folder = folder
                let config = SCStreamConfiguration()
                let rect = filter.contentRect
                let ratio = rect.width > 0 && rect.height > 0 ? rect.width / rect.height : 16.0 / 9.0
                config.width = ratio >= 1 ? 1280 : max(2, Int(1280 * ratio))
                config.height = ratio >= 1 ? max(2, Int(1280 / ratio)) : 1280
                config.minimumFrameInterval = CMTime(value: 1, timescale: 1)
                config.queueDepth = 3
                config.pixelFormat = kCVPixelFormatType_32BGRA
                config.showsCursor = false
                config.capturesAudio = false
                let newStream = SCStream(filter: filter, configuration: config, delegate: self)
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.frameQueue)
                self.stream = newStream
                self.phase = .starting
                self.frameQueue.sync {
                    self.acceptedStream = newStream
                    self.frameFolder = folder
                    self.savedFirst = false
                }
                self.status = "Starting native video capture…"
                self.saveStatus()
                newStream.startCapture { [weak self] error in
                    DispatchQueue.main.async {
                        guard let self, self.stream === newStream, self.phase == .starting else { return }
                        if let error {
                            self.frameQueue.sync { self.acceptedStream = nil }
                            self.stream = nil
                            self.phase = .idle
                            self.picker.isActive = false
                            self.status = "Capture failed: \(error.localizedDescription)"
                        } else {
                            self.phase = .capturing
                            self.status = "Capturing at up to one frame per second. Inspect the video area in the preview."
                            let timer = Timer(timeInterval: 120, repeats: false) { [weak self] _ in self?.stop() }
                            self.stopTimer = timer
                            RunLoop.main.add(timer, forMode: .common)
                        }
                        self.saveStatus()
                    }
                }
            } catch {
                self.phase = .idle
                self.picker.isActive = false
                self.status = "Setup failed: \(error.localizedDescription)"
                self.saveStatus()
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream else { return }
            self.frameQueue.sync { self.acceptedStream = nil }
            self.stopTimer?.invalidate()
            self.stopTimer = nil
            self.stream = nil
            self.phase = .idle
            self.picker.isActive = false
            self.status = "Stream ended: \(error.localizedDescription)"
            self.saveStatus()
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard acceptedStream === stream, type == .screen,
              sample.isValid, CMSampleBufferDataIsReady(sample),
              let attachments = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false) as? [[SCStreamFrameInfo: Any]],
              let state = attachments.first?[.status] as? Int,
              state == SCFrameStatus.complete.rawValue,
              let pixels = sample.imageBuffer, let folder = frameFolder else { return }
        let image = CIImage(cvPixelBuffer: pixels)
        guard let cgImage = context.createCGImage(image, from: image.extent) else { return }
        do {
            let bitmap = NSBitmapImageRep(cgImage: cgImage)
            guard let jpeg = bitmap.representation(using: .jpeg, properties: [.compressionFactor: 0.8]) else {
                throw CocoaError(.fileWriteUnknown)
            }
            if !savedFirst {
                try jpeg.write(to: folder.appendingPathComponent("first.jpg"), options: .atomic)
                savedFirst = true
            }
            try jpeg.write(to: folder.appendingPathComponent("latest.jpg"), options: .atomic)
            let capturedAt = Date()
            DispatchQueue.main.async { [weak self] in
                guard let self, self.stream === stream, self.phase != .stopping else { return }
                self.preview = NSImage(cgImage: cgImage, size: .zero)
                self.frameCount += 1
                self.lastFrameAt = capturedAt
                self.saveStatus()
            }
        } catch {
            acceptedStream = nil
            DispatchQueue.main.async { [weak self] in
                guard let self, self.stream === stream else { return }
                self.stop()
                self.status = "Saving video frame failed: \(error.localizedDescription)"
                self.saveStatus()
            }
        }
    }

    private func saveStatus() {
        guard let folder else { return }
        do {
            let data = try JSONSerialization.data(withJSONObject: [
                "status": status, "frames": frameCount,
                "lastFrameAt": lastFrameAt?.ISO8601Format() as Any? ?? NSNull(),
                "updatedAt": Date().ISO8601Format()
            ], options: [.prettyPrinted, .sortedKeys])
            try data.write(to: folder.appendingPathComponent("status.json"), options: .atomic)
        } catch { status = "Diagnostic save failed: \(error.localizedDescription)" }
    }
}
