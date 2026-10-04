import AppKit
import Combine
import Foundation

@MainActor
final class ProbeModel: ObservableObject {
    @Published var running = false
    @Published var muted = false
    @Published var status = "Ready. Play audio locally, then start capture."
    @Published var source = "Unprotected control"
    @Published var peak = 0.0
    @Published var rms = 0.0
    @Published var callbacks: UInt64 = 0
    @Published var samples: UInt64 = 0
    @Published var secondsRemaining = 0
    @Published var muteSecondsRemaining = 0
    @Published var logPath = "A diagnostic file is created automatically when capture starts."
    @Published var logError: String?

    let logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("SkyboxAudioProbe", isDirectory: true)
    private let tap = AudioTap()
    private var timer: Timer?
    private var stopDeadline = 0.0
    private var muteDeadline: Double?
    private var log: FileHandle?
    private var hasSignal = false
    @Published private(set) var nonzeroIntervals = 0
    private let formatter = ISO8601DateFormatter()

    func start(initialMuteSeconds: Int = 0) {
        guard !running, (0...60).contains(initialMuteSeconds) else { return }
        logError = nil
        peak = 0; rms = 0; callbacks = 0; samples = 0; hasSignal = false; nonzeroIntervals = 0
        do {
            try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
            let url = logDirectory.appendingPathComponent("probe-\(Int(Date().timeIntervalSince1970))-\(UUID().uuidString).jsonl")
            guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
                throw CocoaError(.fileWriteUnknown)
            }
            log = try FileHandle(forWritingTo: url)
            logPath = url.path
            write(["event": "starting", "source": source, "scope": "all-system-output", "version": Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unknown"])
            let format = try tap.start(initiallyMuted: initialMuteSeconds > 0)
            running = true
            muted = initialMuteSeconds > 0
            muteSecondsRemaining = initialMuteSeconds
            muteDeadline = muted ? ProcessInfo.processInfo.systemUptime + Double(initialMuteSeconds) : nil
            if muted { write(["event": "mute-requested", "durationSeconds": initialMuteSeconds, "atTapCreation": true]) }
            stopDeadline = ProcessInfo.processInfo.systemUptime + 180
            secondsRemaining = 180
            status = "Capture started. Waiting for audio samples…"
            write(["event": "started", "sampleRate": format.mSampleRate, "channels": format.mChannelsPerFrame])
            let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated { self?.tick() }
            }
            self.timer = timer
            RunLoop.main.add(timer, forMode: .common)
        } catch {
            status = error.localizedDescription + " Check System Settings → Privacy & Security → Screen & System Audio Recording."
            write(["event": "start-failed", "message": error.localizedDescription])
            closeLog()
        }
    }

    func muteForTenSeconds() { muteFor(seconds: 10) }

    func muteFor(seconds: Int) {
        guard (1...60).contains(seconds) else { return }
        guard running, !muted else { return }
        do {
            try tap.setMuted(true)
            muted = true
            muteDeadline = ProcessInfo.processInfo.systemUptime + Double(seconds)
            muteSecondsRemaining = seconds
            write(["event": "mute-requested", "durationSeconds": seconds])
        } catch {
            stop(reason: "Mute test failed: \(error.localizedDescription)")
        }
    }

    func restoreOutput() {
        guard running, muted else { return }
        do {
            try tap.setMuted(false)
            muted = false
            muteDeadline = nil
            muteSecondsRemaining = 0
            write(["event": "output-restored"])
        } catch {
            stop(reason: "Restore failed: \(error.localizedDescription)")
        }
    }

    func stop(reason: String = "Stopped") {
        timer?.invalidate()
        timer = nil
        let errors = tap.stop()
        running = false
        muted = false
        muteDeadline = nil
        secondsRemaining = 0
        muteSecondsRemaining = 0
        status = errors.isEmpty ? "\(reason). Capture ended; tap removed." : "\(reason). Cleanup errors: \(errors.joined(separator: "; "))"
        write(["event": "stopped", "reason": reason, "cleanupErrors": errors,
               "totalCallbacks": callbacks, "totalSamples": samples, "nonzeroObserved": hasSignal])
        closeLog()
    }

    func showLogs() { NSWorkspace.shared.open(logDirectory) }

    private func tick() {
        guard running else { return }
        let now = ProcessInfo.processInfo.systemUptime
        // Attribute this completed measurement interval to the mute state before changing it.
        let reading = tap.takeReading()
        callbacks += reading.callbacks
        samples += reading.samples
        peak = reading.levels?.peak ?? 0
        rms = reading.levels?.rms ?? 0
        hasSignal = hasSignal || peak > 0
        if peak > 0 && reading.invalidSamples == 0 && reading.malformedBuffers == 0 { nonzeroIntervals += 1 }
        if reading.invalidSamples > 0 || reading.malformedBuffers > 0 {
            status = "Invalid audio data received; this interval is inconclusive."
        } else if reading.callbacks == 0 {
            status = "No audio callbacks this second. Capture is not yet confirmed."
        } else if reading.samples == 0 {
            status = "Callbacks received, but no audio samples."
        } else if peak == 0 {
            status = "Samples received, all zero this second. Silence or unavailable audio."
        } else {
            status = muted ? "Nonzero audio received during the mute test." : "Nonzero system audio received."
        }
        write(["event": "measurement", "mutedRequested": muted, "callbacks": reading.callbacks,
               "samples": reading.samples, "invalidSamples": reading.invalidSamples,
               "malformedBuffers": reading.malformedBuffers,
               "peak": reading.levels.map { $0.peak as Any } ?? NSNull(),
               "rms": reading.levels.map { $0.rms as Any } ?? NSNull()])
        if let deadline = muteDeadline {
            muteSecondsRemaining = max(0, Int(ceil(deadline - now)))
            if now >= deadline { restoreOutput() }
        }
        guard running else { return }
        secondsRemaining = max(0, Int(ceil(stopDeadline - now)))
        if now >= stopDeadline { stop(reason: "Three-minute test finished") }
    }

    private func write(_ fields: [String: Any]) {
        guard let log else { return }
        do {
            var entry = fields
            entry["timestamp"] = formatter.string(from: Date())
            var data = try JSONSerialization.data(withJSONObject: entry, options: [.sortedKeys])
            data.append(0x0a)
            try log.write(contentsOf: data)
        } catch {
            logError = "Diagnostic save failed: \(error.localizedDescription)"
        }
    }

    private func closeLog() {
        do { try log?.close() } catch { logError = "Closing diagnostic file failed: \(error.localizedDescription)" }
        log = nil
    }
}
