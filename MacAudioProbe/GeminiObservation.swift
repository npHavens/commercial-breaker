import Foundation
import Combine

/// Development-only bridge to the Node worker in this checkout's Tools directory.
/// Observation has no references to routing or mute controls.
@MainActor
final class GeminiObservation: ObservableObject {
    enum Sport: String, CaseIterable { case football = "Football", ufc = "UFC" }
    @Published private(set) var enabled = false
    @Published private(set) var status = "Gemini is off · audio stays local"
    @Published private(set) var prediction = ""
    @Published private(set) var confirmation = "Waiting for two matching predictions"
    private var confirmer = GeminiConfirmation()
    var onConfirmed: ((GeminiConfirmation.State) -> Void)?
    let buffer = GeminiAudioBuffer()
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var received = Data()
    private var timer: Timer?
    private var generation = UUID()
    private var request: (id: String, generation: UUID, start: Double, end: Double, sent: Double, audio: Data?)?
    private var retainProgramAudio = false
    private var diagnosticSlot = 0
    private var workerReady = false
    private var recovery = GeminiRecovery()
    private var directory: URL?
    private var lastPredictionTime = 0.0
    private static let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()

    private let makeWorker: @MainActor () throws -> Process

    init(makeWorker: @escaping @MainActor () throws -> Process = GeminiObservation.makeWorker) {
        self.makeWorker = makeWorker
    }

    func start(directory: URL, retainProgramAudio: Bool = false, sport: Sport = .football, returnDetection: Bool = false) {
        guard !enabled else { return }
        self.directory = directory
        self.retainProgramAudio = retainProgramAudio
        generation = UUID()
        buffer.reset()
        recovery = GeminiRecovery()
        lastAudioEndSent = nil
        lastSent = 0
        preparing = nil
        prediction = ""
        resetConfirmation()
        enabled = true
        status = "Starting Gemini · sends audio to Google Vertex AI"
        do {
            let child = try makeWorker()
            child.environment = Self.workerEnvironment(child.environment ?? ProcessInfo.processInfo.environment, sport: sport, returnDetection: returnDetection)
            let stdin = Pipe(), stdout = Pipe()
            child.standardInput = stdin
            child.standardOutput = stdout
            // The worker emits sanitized errors on stdout. Never persist SDK stderr.
            child.standardError = FileHandle.nullDevice
            stdout.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                Task { @MainActor in
                    guard let self, self.process === child, self.enabled else { return }
                    self.receive(data)
                }
            }
            child.terminationHandler = { [weak self] _ in
                Task { @MainActor in
                    guard let self, self.process === child, self.enabled else { return }
                    self.stop(message: "Gemini stopped · worker exited. Recording continues.")
                }
            }
            process = child
            input = stdin.fileHandleForWriting
            output = stdout.fileHandleForReading
            try child.run()
            log(["event": "enabled", "sport": sport.rawValue, "model": "gemini-3.8-flash", "windowSeconds": 8, "intervalSeconds": 5, "confirmationIntervalSeconds": 1, "timerSeconds": 0.25])
            timer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
                Task { @MainActor in await self?.tick() }
            }
            Task { [weak self] in
                try? await Task.sleep(for: .seconds(20))
                guard let self, self.process === child, self.enabled, !self.workerReady else { return }
                self.stop(message: "Gemini startup timed out · recording continues")
            }
        } catch {
            stop(message: "Gemini could not start · install Node 24 with nvm. Recording continues.")
        }
    }

    func resetContext() {
        generation = UUID()
        buffer.reset()
        prediction = ""
        resetConfirmation()
        if enabled {
            status = "Game changed · waiting for eight seconds of new audio"
            log(["event": "context-reset"])
        }
    }

    func stop(message: String = "Gemini is off · no further audio is sent") {
        let wasEnabled = enabled
        enabled = false
        generation = UUID()
        timer?.invalidate(); timer = nil
        output?.readabilityHandler = nil
        try? input?.close(); input = nil
        if let child = process, child.isRunning { child.terminate() }
        process = nil
        try? output?.close(); output = nil
        received.removeAll()
        request = nil
        preparing = nil
        workerReady = false
        buffer.reset()
        prediction = ""
        resetConfirmation()
        status = message
        if wasEnabled { log(["event": "disabled", "message": message]) }
    }

    private func tick() async {
        guard enabled, workerReady else { return }
        let now = ProcessInfo.processInfo.systemUptime
        if let end = confirmer.lastEnd, now - end > 15 {
            prediction = "No recent prediction"
            resetConfirmation()
            log(["event": "confirmation-reset", "reason": "stale audio"])
        }
        if let request {
            if now - request.sent > 25 { stop(message: "Gemini request timed out · recording continues") }
            return
        }
        let fastFollowUp = confirmer.needsFastFollowUp
        let interval = fastFollowUp ? 1.0 : 5.0
        guard now >= recovery.resumeAt, now - lastSent >= interval, preparing == nil else { return }
        let preparation = UUID()
        preparing = preparation
        let context = generation
        let worker = process
        let ring = buffer
        let sample = await Task.detached(priority: .utility) { ring.snapshot() }.value
        guard preparing == preparation else { return }
        preparing = nil
        guard enabled, context == generation, request == nil else { return }
        guard let sample else {
            status = "Waiting for eight seconds of continuous, recent audio"
            return
        }
        // Even very fast responses cannot confirm twice from the same audio.
        guard lastAudioEndSent.map({ sample.endUptime - $0 >= 1 }) ?? true else { return }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased().prefix(12)
        do {
            var data = try JSONSerialization.data(withJSONObject: ["id": String(id), "audio": sample.wavData.base64EncodedString()])
            data.append(10)
            request = (String(id), context, sample.startUptime, sample.endUptime, now, retainProgramAudio ? sample.wavData : nil)
            lastSent = ProcessInfo.processInfo.systemUptime
            lastAudioEndSent = sample.endUptime
            status = "Checking recent audio · playback unchanged"
            log(["event": "request", "id": String(id), "startUptime": sample.startUptime, "endUptime": sample.endUptime, "fastFollowUp": fastFollowUp])
            guard let input else { throw CocoaError(.fileWriteUnknown) }
            let payload = data
            try await Task.detached(priority: .utility) { try input.write(contentsOf: payload) }.value
        } catch {
            guard enabled, process === worker else { return }
            stop(message: "Gemini connection failed · recording continues")
        }
    }
    private var lastAudioEndSent: Double?
    private var lastSent = 0.0
    private var preparing: UUID?

    private func receive(_ data: Data) {
        guard !data.isEmpty else { return }
        received.append(data)
        guard received.count <= 64_000 else { stop(message: "Gemini returned an invalid response"); return }
        while let newline = received.firstIndex(of: 10) {
            let line = received.prefix(upTo: newline)
            received.removeSubrange(...newline)
            guard let value = try? JSONSerialization.jsonObject(with: line) as? [String: Any] else {
                stop(message: "Gemini returned an invalid response"); return
            }
            if value["ready"] as? Bool == false {
                stop(message: Self.setupMessage(value["error"] as? String)); return
            }
            if value["ready"] as? Bool == true {
                if let hash = value["promptSHA256"] as? String,
                   hash.count == 64, hash.allSatisfy({ $0.isHexDigit }) {
                    log(["event": "worker-ready", "promptSHA256": hash])
                }
                workerReady = true
                status = "Gemini ready · waiting for eight seconds of audio"
                continue
            }
            guard let pending = request, value["id"] as? String == pending.id else {
                stop(message: "Gemini worker reported an unexpected response"); return
            }
            request = nil
            if let error = value["error"] as? String {
                let allowed = ["invalid-request", "busy", "timeout", "temporary-failure", "incomplete-response", "invalid-response", "request-failed"]
                log(["event": "request-failed", "id": pending.id, "error": allowed.contains(error) ? error : "unknown",
                     "httpStatus": (value["httpStatus"] as? Int).map { (100...599).contains($0) ? $0 : 0 } ?? 0])
                prediction = ""
                resetConfirmation()
                let retryable = GeminiRecovery.allowsRetry(error: error, httpStatus: value["httpStatus"] as? Int)
                if retryable, let delay = recovery.failed(now: ProcessInfo.processInfo.systemUptime) {
                    status = "Gemini request failed · checking fresh audio in \(Int(delay)) seconds"
                    log(["event": "request-recovery", "delaySeconds": delay,
                         "consecutiveFailures": recovery.consecutiveFailures])
                    continue
                }
                stop(message: retryable
                     ? "Gemini stopped after three consecutive request failures · recording continues"
                     : "Gemini request failed · recording continues. See the session log."); return
            }
            recovery.succeeded()
            guard pending.generation == generation else {
                log(["event": "discarded-stale-response", "id": pending.id]); continue
            }
            guard let result = value["result"] as? [String: Any],
                  let state = result["state_at_end"] as? String,
                  ["program", "commercial", "promo", "unclear", "not_program", "unusable"].contains(state),
                  let elapsed = value["elapsedMs"] as? Double else {
                stop(message: "Gemini returned an invalid prediction"); return
            }
            lastPredictionTime = ProcessInfo.processInfo.systemUptime
            guard lastPredictionTime - pending.end <= 15 else {
                resetConfirmation()
                log(["event": "discarded-old-response", "id": pending.id]); continue
            }
            if state == "program", let audio = pending.audio {
                saveProgramAudio(audio, id: pending.id, result: result,
                                 start: pending.start, end: pending.end)
            }
            let label = state == "not_program" ? "No sport coverage" : state == "unusable" ? "Audio unusable" : state.capitalized
            prediction = "\(label) · \(Date().formatted(date: .omitted, time: .standard)) · \(String(format: "%.1f", elapsed / 1000))s response"
            let changed = confirmer.accept(state, end: pending.end)
            confirmation = confirmer.display
            status = "Gemini observation only · playback unchanged"
            log(["event": "confirmation", "id": pending.id,
                 "candidate": confirmer.candidate?.rawValue ?? "unclear", "count": confirmer.count,
                 "confirmed": confirmer.confirmed?.rawValue ?? "unknown", "changed": changed,
                 "endUptime": pending.end])
            log(["event": "prediction", "id": pending.id, "startUptime": pending.start, "endUptime": pending.end,
                 "result": result, "elapsedMs": elapsed, "usage": value["usage"] ?? NSNull()])
            if changed, let confirmed = confirmer.confirmed { onConfirmed?(confirmed) }
            if confirmer.needsFastFollowUp {
                Task { [weak self] in await self?.tick() }
            }
        }
    }

    // Fixed six-slot ring across capture legs: at most 48 seconds of system audio.
    private func saveProgramAudio(_ audio: Data, id: String, result: [String: Any], start: Double, end: Double) {
        guard let directory else { return }
        let folder = directory.deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("return-audio-diagnostics")
        let stem = "sample-\(diagnosticSlot)"
        diagnosticSlot = (diagnosticSlot + 1) % 6
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try audio.write(to: folder.appendingPathComponent(stem + ".wav"), options: .atomic)
            let metadata: [String: Any] = ["id": id, "session": directory.lastPathComponent,
                "startUptime": start, "endUptime": end, "result": result,
                "savedAt": ISO8601DateFormatter().string(from: Date())]
            try JSONSerialization.data(withJSONObject: metadata).write(
                to: folder.appendingPathComponent(stem + ".json"), options: .atomic)
            log(["event": "program-audio-saved", "id": id, "slot": stem])
        } catch { log(["event": "program-audio-save-failed", "id": id]) }
    }

    private func resetConfirmation() {
        confirmer.reset()
        confirmation = "Waiting for two matching predictions"
    }

    private func log(_ value: [String: Any]) {
        guard let directory else { return }
        var record = value
        record["uptime"] = ProcessInfo.processInfo.systemUptime
        record["date"] = ISO8601DateFormatter().string(from: Date())
        guard var data = try? JSONSerialization.data(withJSONObject: record) else { return }
        data.append(10)
        let url = directory.appendingPathComponent("gemini-observations.jsonl")
        if !FileManager.default.fileExists(atPath: url.path) { FileManager.default.createFile(atPath: url.path, contents: nil) }
        do {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd(); try handle.write(contentsOf: data)
        } catch {
            status = "Gemini log could not be saved"
        }
    }

    static func workerEnvironment(_ base: [String: String], sport: Sport, returnDetection: Bool) -> [String: String] {
        var environment = base
        environment["COMMERCIAL_BREAKER_SPORT"] = sport == .football ? "football" : "ufc"
        environment["COMMERCIAL_BREAKER_RETURN_DETECTION"] = returnDetection ? "1" : "0"
        return environment
    }

    static func setupMessage(_ error: String?) -> String {
        switch error {
        case "dependencies-missing": "Gemini could not start · run npm ci in the Skybox checkout. Recording continues."
        case "configuration-missing": "Gemini could not start · set GOOGLE_CLOUD_PROJECT in the Skybox .env. Recording continues."
        case "app-rebuild-required": "Gemini could not start · rebuild the app from this checkout. Recording continues."
        default: "Gemini could not start · see Gemini setup in the README. Recording continues."
        }
    }

    /// Settings come from the ignored `.env` beside this checkout's `package.json`.
    static func makeWorker() throws -> Process {
        let child = Process()
        child.executableURL = try nodeURL(home: FileManager.default.homeDirectoryForCurrentUser)
        child.arguments = ["--env-file-if-exists=" + root.appendingPathComponent(".env").path,
                           root.appendingPathComponent("Tools/gemini-live-worker.mjs").path]
        child.currentDirectoryURL = root
        return child
    }

    private static func nodeURL(home: URL) throws -> URL {
        let fm = FileManager.default
        let versions = home.appendingPathComponent(".nvm/versions/node")
        let installed = (try? fm.contentsOfDirectory(at: versions, includingPropertiesForKeys: nil)) ?? []
        let candidates = installed.filter { $0.lastPathComponent.hasPrefix("v24.") }
            .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedDescending }
            .map { $0.appendingPathComponent("bin/node") }
        guard let node = candidates.first(where: { fm.isExecutableFile(atPath: $0.path) }) else { throw CocoaError(.fileNoSuchFile) }
        return node
    }
}
