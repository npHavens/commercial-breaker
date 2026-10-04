import Combine
import CoreImage
import ScreenCaptureKit
import UIKit

/// Real-device experiment; capturing other apps is deliberately an unproven capability.
final class CaptureProbe: NSObject, ObservableObject, SCContentSharingPickerObserver, SCStreamDelegate, SCStreamOutput {
    enum Phase { case idle, choosing, starting, capturing, stopping }

    struct Frame: Identifiable {
        let url: URL
        let savedAt: Date
        var id: String { url.lastPathComponent }
    }

    @Published private(set) var phase: Phase = .idle
    @Published private(set) var status = "Ready"
    @Published private(set) var frames: [Frame] = []
    @Published private(set) var events: [String] = []
    @Published private(set) var lastFrameAt: Date?

    private let picker = SCContentSharingPicker.shared
    private var stream: SCStream?
    private let context = CIContext()
    private let frameQueue = DispatchQueue(label: "skybox.frames")
    // Accessed only on frameQueue. Control/UI state is confined to the main queue.
    private var sampler = FrameSampler(interval: 20)
    private var acceptedStream: SCStream?
    private var receivedFirstBuffer = false
    private var reportedSkips: Set<String> = []
    private let directory: URL

    override init() {
        directory = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("CaptureProbe", isDirectory: true)
        super.init()
        picker.add(self)
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let text = (try? String(contentsOf: directory.appendingPathComponent("events.log"), encoding: .utf8)) ?? ""
            events = text.split(separator: "\n").suffix(1000).map(String.init)
            try reloadFrames()
            recordEvent("Window probe opened; ScreenCaptureKit available: \(picker.isAvailable)")
        } catch { status = "Storage error: \(error.localizedDescription)" }
    }

    deinit { picker.remove(self) }

    func start() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .idle else { return }
        guard picker.isAvailable else {
            updateStatus("ScreenCaptureKit is unavailable on this device right now")
            return
        }
        phase = .choosing
        lastFrameAt = nil
        frameQueue.sync {
            sampler.reset()
            receivedFirstBuffer = false
            reportedSkips.removeAll()
        }
        updateStatus("Opening window picker — inspect which sources it offers")
        picker.isActive = true
        picker.present(using: .window)
    }

    func stop() {
        dispatchPrecondition(condition: .onQueue(.main))
        guard phase == .capturing, let stream else { return }
        finish(stream, message: "Stopping")
    }

    private func finish(_ endingStream: SCStream, message: String) {
        guard stream === endingStream, phase != .stopping else { return }
        phase = .stopping
        updateStatus(message)
        frameQueue.sync { acceptedStream = nil }
        picker.isActive = false
        endingStream.stopCapture { [weak self] error in
            DispatchQueue.main.async {
                guard let self, self.stream === endingStream else { return }
                self.stream = nil
                self.phase = .idle
                if let error { self.updateStatus("Stop error: \(error as NSError)") }
                else if message == "Stopping" { self.updateStatus("Stopped") }
                else { self.recordEvent("Stream cleanup finished") }
            }
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker, didCancelFor stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            self.picker.isActive = false
            self.phase = .idle
            self.updateStatus("Window picker canceled")
        }
    }

    func contentSharingPickerStartDidFailWithError(_ error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            self.picker.isActive = false
            self.phase = .idle
            self.updateStatus("Window picker failed: \(error as NSError)")
        }
    }

    func contentSharingPicker(_ picker: SCContentSharingPicker,
                              didUpdateWith filter: SCContentFilter, for stream: SCStream?) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.phase == .choosing else { return }
            self.recordEvent("Picker selected style \(filter.style.rawValue); rect \(filter.contentRect); scale \(filter.pointPixelScale). Source app identity is not exposed by this tvOS filter.")
            let newStream = SCStream(filter: filter, configuration: SCStreamConfiguration(), delegate: self)
            do {
                try newStream.addStreamOutput(self, type: .screen, sampleHandlerQueue: self.frameQueue)
            } catch {
                self.picker.isActive = false
                self.phase = .idle
                self.updateStatus("Stream setup failed: \(error as NSError)")
                return
            }
            self.stream = newStream
            self.phase = .starting
            self.frameQueue.sync { self.acceptedStream = newStream }
            self.updateStatus("Starting window stream — waiting for frames")
            newStream.startCapture { [weak self] error in
                DispatchQueue.main.async {
                    guard let self, self.stream === newStream, self.phase == .starting else { return }
                    if let error {
                        self.finish(newStream, message: "Capture start failed: \(error as NSError)")
                    } else {
                        self.phase = .capturing
                        self.updateStatus("Window stream started — saved images are the evidence")
                    }
                }
            }
        }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        DispatchQueue.main.async { [weak self] in
            guard let self, self.stream === stream, self.phase != .stopping else { return }
            self.frameQueue.sync { self.acceptedStream = nil }
            self.stream = nil
            self.picker.isActive = false
            self.phase = .idle
            self.updateStatus("Window stream ended: \(error as NSError)")
        }
    }

    /// ScreenCaptureKit invokes this on frameQueue; processing stays serial with buffer delivery.
    func stream(_ stream: SCStream, didOutputSampleBuffer buffer: CMSampleBuffer,
                of type: SCStreamOutputType) {
        dispatchPrecondition(condition: .onQueue(frameQueue))
        guard acceptedStream === stream, type == .screen else { return }
        if !receivedFirstBuffer {
            receivedFirstBuffer = true
            recordEvent("First window video buffer received")
        }
        guard CMSampleBufferIsValid(buffer), CMSampleBufferDataIsReady(buffer) else {
            reportSkip("invalid or unready sample buffer")
            return
        }
        if let attachments = CMSampleBufferGetSampleAttachmentsArray(buffer, createIfNecessary: false)
            as? [[SCStreamFrameInfo: Any]],
           let status = attachments.first?[.status] as? Int,
           status != SCFrameStatus.complete.rawValue {
            reportSkip("frame status \(status) (0 complete, 1 idle, 2 blank, 3 suspended, 4 started, 5 stopped)")
            return
        }
        let time = CMSampleBufferGetPresentationTimeStamp(buffer).seconds
        guard time.isFinite else { reportSkip("nonfinite video timestamp"); return }
        guard sampler.isDue(time) else { return }
        guard let pixels = CMSampleBufferGetImageBuffer(buffer) else {
            reportSkip("no image buffer")
            return
        }
        do {
            let image = CIImage(cvPixelBuffer: pixels)
            let url = directory.appendingPathComponent("\(UUID().uuidString).jpg")
            try context.writeJPEGRepresentation(of: image, to: url,
                colorSpace: CGColorSpaceCreateDeviceRGB(), options: [:])
            sampler.didSave(time)
            let savedAt = Date()
            try trimFrames()
            let dimensions = "\(CVPixelBufferGetWidth(pixels))x\(CVPixelBufferGetHeight(pixels))"
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                // A frame written before Stop still belongs in the persisted gallery.
                do { try self.reloadFrames() }
                catch {
                    if self.stream === stream { self.finish(stream, message: "Storage error: \(error as NSError)") }
                    return
                }
                if self.stream === stream { self.lastFrameAt = savedAt }
                self.recordEvent("Saved window frame \(url.lastPathComponent); captured at \(savedAt.ISO8601Format()); video time \(time); \(dimensions)")
            }
        } catch {
            acceptedStream = nil
            DispatchQueue.main.async { [weak self] in
                self?.finish(stream, message: "Frame write failed: \(error as NSError)")
            }
        }
    }

    private func reportSkip(_ reason: String) {
        if reportedSkips.insert(reason).inserted { recordEvent("Skipped buffer: \(reason)") }
    }

    private func storedFrames() throws -> [Frame] {
        try FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.contentModificationDateKey])
            .filter { $0.pathExtension == "jpg" }
            .map { Frame(url: $0, savedAt: try $0.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate ?? .distantPast) }
            .sorted { $0.savedAt > $1.savedAt }
    }

    private func trimFrames() throws {
        for frame in try storedFrames().dropFirst(100) {
            try FileManager.default.removeItem(at: frame.url)
        }
    }

    private func reloadFrames() throws { frames = try storedFrames() }

    private func updateStatus(_ value: String) {
        status = value
        recordEvent(value)
    }

    func recordEvent(_ message: String) {
        if !Thread.isMainThread {
            DispatchQueue.main.async { [weak self] in self?.recordEvent(message) }
            return
        }
        events.append("\(Date().ISO8601Format()) \(message)")
        events = Array(events.suffix(1000))
        do {
            try (events.joined(separator: "\n") + "\n").write(
                to: directory.appendingPathComponent("events.log"), atomically: true, encoding: .utf8)
        } catch { status = "Log write failed: \(error.localizedDescription)" }
    }

}
