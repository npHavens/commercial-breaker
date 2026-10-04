import AVFoundation
import Combine

@MainActor
final class AudioRecorderModel: ObservableObject {
    enum Source: String, CaseIterable {
        case microphone = "Microphone · TV / AirPlay"
        case system = "System audio · Mac playback"
    }

    @Published var source: Source = .microphone
    @Published private(set) var running = false
    @Published private(set) var ready = false
    @Published private(set) var status = "Choose the source you are listening to, then start."
    @Published private(set) var history = ""
    @Published private(set) var rms = 0.0
    @Published private(set) var secondsRemaining: Int? = 900
    @Published private(set) var folder: URL?
    @Published private(set) var cues: LiveCueReading?
    @Published private(set) var cueStatus = "Sound analysis starts with recording."
    @Published private(set) var markedContext = "Unknown · waiting for your marker"
    @Published private(set) var candidateCount = 0
    @Published private(set) var lastCandidateAt: Date?
    private(set) var lastStopErrors: [String] = []
    let gemini = GeminiObservation()
    private let microphone = MicrophoneInput()
    private var tap: AudioTap?
    private var store: AudioClipStore?
    private var cueAnalyzer: LiveAudioCues?
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var session: UUID?
    private var lastMeterTime = 0.0
    private var cueContextStart = 0.0

    func start(initiallyMuted: Bool = false, sessionLimitSeconds: Int? = 900) {
        guard !running, !initiallyMuted || source == .system else { return }
        let id = UUID()
        session = id
        running = true
        ready = false
        secondsRemaining = sessionLimitSeconds
        lastMeterTime = 0
        rms = 0
        history = ""
        cues = nil
        cueStatus = "Preparing local sound analysis…"
        markedContext = "Unknown · waiting for your marker"
        candidateCount = 0
        lastCandidateAt = nil
        cueContextStart = ProcessInfo.processInfo.systemUptime
        status = "Starting capture…"
        let selected = source
        task = Task { [self] in
            guard session == id, running, !Task.isCancelled else { return }
            do {
                let base = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                let directory = base.appendingPathComponent("SkyboxAudioProbe/recordings/\(id.uuidString)", isDirectory: true)
                let recorder = try AudioClipStore(directory: directory, source: selected.rawValue) { [weak self] message in
                    Task { @MainActor in
                        guard self?.session == id else { return }
                        self?.record(message)
                    }
                }
                store = recorder
                folder = directory
                // Analysis is optional: failure must never stop capture or clip saving.
                let analysis: LiveAudioCues?
                do {
                    analysis = try LiveAudioCues(directory: directory, onUpdate: { [weak self] reading in
                        Task { @MainActor in
                            guard let self, self.session == id, self.running,
                                  reading.startUptime >= self.cueContextStart else { return }
                            self.cues = reading
                            self.cueStatus = "Live sound scores · observation only"
                        }
                    }, onStatus: { [weak self] message in
                        Task { @MainActor in
                            guard let self, self.session == id, self.running else { return }
                            self.cueStatus = message
                            self.cues = nil
                        }
                    }, onCandidate: { [weak self] candidate in
                        Task { @MainActor in
                            guard let self, self.session == id, self.running,
                                  candidate.evidenceStartUptime >= self.cueContextStart else { return }
                            self.candidateCount += 1
                            self.lastCandidateAt = Date(timeIntervalSinceNow:
                                candidate.detectedAtUptime - ProcessInfo.processInfo.systemUptime)
                            self.record("Possible break cue · music rose as crowd faded. Observation only; playback unchanged.")
                        }
                    })
                    cueAnalyzer = analysis
                    cueStatus = "Waiting for the first few seconds of audio…"
                } catch {
                    analysis = nil
                    cueStatus = "Sound analysis unavailable: \(error.localizedDescription). Recording can continue."
                }
                let geminiBuffer = gemini.buffer
                if selected == .microphone {
                    try await microphone.start { [weak self] samples, rate, end in
                        recorder.ingest(samples, sampleRate: rate, endedAt: end)
                        geminiBuffer.ingest(samples, sampleRate: rate, endedAt: end)
                        analysis?.ingest(samples: samples, sampleRate: rate, endedAt: end)
                        guard let self, self.session == id, end - self.lastMeterTime >= 0.25 else { return }
                        self.lastMeterTime = end
                        self.rms = AudioLevels.measure(samples)?.rms ?? 0
                    } onFailure: { [weak self] message in
                        self?.stop(reason: message)
                    }
                } else {
                    let capture = AudioTap()
                    tap = capture
                    _ = try capture.start(initiallyMuted: initiallyMuted, onAudio: { samples, rate, end in
                        recorder.ingest(samples, sampleRate: rate, endedAt: end)
                        geminiBuffer.ingest(samples, sampleRate: rate, endedAt: end)
                        analysis?.ingest(samples: samples, sampleRate: rate, endedAt: end)
                    }, onAudioError: { [weak self] message in
                        Task { @MainActor in
                            guard self?.session == id else { return }
                            self?.stop(reason: message)
                        }
                    })
                }
                guard session == id, !Task.isCancelled else { return }
                ready = true
                secondsRemaining = sessionLimitSeconds
                let deadline = sessionLimitSeconds.map { ProcessInfo.processInfo.systemUptime + Double($0) }
                timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
                    Task { @MainActor in
                        guard let self, self.running, self.session == id else { return }
                        if let tap = self.tap { self.rms = tap.takeReading().levels?.rms ?? 0 }
                        if let cues = self.cues,
                           ProcessInfo.processInfo.systemUptime - cues.endUptime > 8 {
                            self.cues = nil
                            self.cueStatus = "No recent sound-analysis result · recording continues"
                        }
                        if let deadline {
                            self.secondsRemaining = max(0, Int(ceil(deadline - ProcessInfo.processInfo.systemUptime)))
                            if self.secondsRemaining == 0 { self.stop(reason: "Recording time limit reached") }
                        }
                    }
                }
                record("Listening · mark commercial starts and program returns. Clips save 10 seconds after each marker.")
            } catch {
                guard session == id, running, !Task.isCancelled else { return }
                stop(reason: error.localizedDescription)
            }
        }
    }

    func setSystemMuted(_ muted: Bool) throws {
        guard running, ready, source == .system, let tap else {
            throw RoutingFailure(message: "System capture is not ready; mute was not changed.")
        }
        try tap.setMuted(muted)
        record(muted ? "Automatic system mute requested" : "Automatic system sound restored")
    }

    func mark(_ label: String) {
        guard ready, let store else { return }
        store.mark(label, at: ProcessInfo.processInfo.systemUptime)
        switch label {
        case "Commercial started": markedContext = "Commercial · marked by you"
        case "Football returned", "Program returned": markedContext = "Program · marked by you"
        case "Changed game", "Changed channel":
            markedContext = "Unknown · channel changed"
            cueContextStart = ProcessInfo.processInfo.systemUptime
            cues = nil
            lastCandidateAt = nil
            cueAnalyzer?.reset(reason: "Game changed")
            gemini.resetContext()
        default: break
        }
        record("Marked: \(label)")
    }

    func stop(reason: String = "Stopped · pending clips saved with the audio available") {
        ready = false
        gemini.stop()
        task?.cancel()
        task = nil
        timer?.invalidate()
        timer = nil
        microphone.stop()
        let errors = tap?.stop() ?? []
        lastStopErrors = errors
        tap = nil
        cueAnalyzer?.stop()
        cueAnalyzer = nil
        store?.stop()
        store = nil
        running = false
        cues = nil
        cueStatus = "Sound analysis stopped. Saved scores remain in the session folder."
        rms = 0
        record(([reason] + errors).joined(separator: " · "))
    }

    private func record(_ message: String) {
        status = message
        let line = "\(Date().formatted(date: .omitted, time: .standard)) · \(message)"
        history = (history.split(separator: "\n").suffix(39).map(String.init) + [line]).joined(separator: "\n")
    }
}
