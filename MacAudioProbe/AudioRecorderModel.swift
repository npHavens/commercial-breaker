import AVFoundation
import Combine

/// Capture for Automatic: feeds Gemini's buffer from the microphone or the
/// system tap and owns the tap's mute. No audio is written here.
@MainActor
final class AudioRecorderModel: ObservableObject {
    enum Source: String, CaseIterable {
        case microphone = "Microphone · TV / AirPlay"
        case system = "System audio · Mac playback"
    }

    @Published var source: Source = .microphone
    @Published private(set) var running = false
    @Published private(set) var ready = false
    @Published private(set) var status = "Not listening"
    @Published private(set) var folder: URL?
    private(set) var lastStopErrors: [String] = []
    let gemini = GeminiObservation()
    private let microphone = MicrophoneInput()
    private var tap: AudioTap?
    private var task: Task<Void, Never>?
    private var session: UUID?

    func start(initiallyMuted: Bool = false) {
        guard !running, !initiallyMuted || source == .system else { return }
        let id = UUID()
        session = id
        running = true
        ready = false
        status = "Starting capture…"
        let selected = source
        task = Task { [self] in
            guard session == id, running, !Task.isCancelled else { return }
            do {
                let base = try FileManager.default.url(for: .applicationSupportDirectory,
                    in: .userDomainMask, appropriateFor: nil, create: true)
                let directory = base.appendingPathComponent("SkyboxAudioProbe/recordings/\(id.uuidString)", isDirectory: true)
                // Holds this session's Gemini log and any opt-in diagnostic samples.
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                folder = directory
                let geminiBuffer = gemini.buffer
                if selected == .microphone {
                    try await microphone.start { samples, rate, end in
                        geminiBuffer.ingest(samples, sampleRate: rate, endedAt: end)
                    } onFailure: { [weak self] message in
                        self?.stop(reason: message)
                    }
                } else {
                    let capture = AudioTap()
                    tap = capture
                    _ = try capture.start(initiallyMuted: initiallyMuted, onAudio: { samples, rate, end in
                        geminiBuffer.ingest(samples, sampleRate: rate, endedAt: end)
                    }, onAudioError: { [weak self] message in
                        Task { @MainActor in
                            guard self?.session == id else { return }
                            self?.stop(reason: message)
                        }
                    })
                }
                guard session == id, !Task.isCancelled else { return }
                ready = true
                status = "Listening"
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
        status = muted ? "Automatic system mute requested" : "Automatic system sound restored"
    }

    func stop(reason: String = "Stopped") {
        ready = false
        gemini.stop()
        task?.cancel()
        task = nil
        microphone.stop()
        let errors = tap?.stop() ?? []
        lastStopErrors = errors
        tap = nil
        running = false
        status = ([reason] + errors).joined(separator: " · ")
    }
}
