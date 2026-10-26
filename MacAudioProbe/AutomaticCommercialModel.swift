import Foundation
import Combine
import CoreGraphics

/// Coordinates the tested route and capture components. No raw model output can
/// request an action; only the two-result confirmer enters this state machine.
@MainActor
final class AutomaticCommercialModel: ObservableObject {
    enum Playback: String, CaseIterable { case mac = "Mac playback", airPlay = "TV via AirPlay" }
    @Published var sport: GeminiObservation.Sport = .football
    @Published var playback: Playback = .mac
    @Published private(set) var enabled = false
    @Published private(set) var recovering = false
    @Published private(set) var status = "Ready for a supervised automatic test"
    @Published private(set) var history = ""
    @Published private(set) var phase = AutomaticCommercialPolicy.Phase.idle
    var busy: Bool { enabled || recovering }
    private let recorder: AudioRecorderModel
    private let routing: RoutingModel
    private var policy = AutomaticCommercialPolicy()
    private var task: Task<Void, Never>?
    private var timer: Timer?
    private var awakeActivity: NSObjectProtocol?
    private let viewingActivity = ViewingActivity()
    private var viewingActivityFailed = false
    private var generation = UUID()
    private var pickerRetryAfter: Double?
    private var mutedSince: Double?
    private var logURL: URL?
    private var mayHaveChangedRoute = false
    private var tv = ""
    private var local = ""

    init(recorder: AudioRecorderModel, routing: RoutingModel) {
        self.recorder = recorder
        self.routing = routing
    }

    func start() {
        guard !busy, !recorder.running, !routing.busy else { return }
        tv = routing.tvName.trimmingCharacters(in: .whitespacesAndNewlines)
        local = routing.localName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard playback == .mac || (!tv.isEmpty && !local.isEmpty && tv != local) else {
            status = "Enter different exact Mac and TV labels in the AirPlay tab first."
            return
        }
        generation = UUID()
        let id = generation
        enabled = true
        history = ""
        mayHaveChangedRoute = false
        pickerRetryAfter = nil
        policy.begin(); phase = policy.phase
        do {
            let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                   appropriateFor: nil, create: true)
                .appendingPathComponent(applicationSupportDirectoryName)
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
            logURL = base.appendingPathComponent("automatic-\(id.uuidString).jsonl")
        } catch {
            enabled = false; policy.stop(); phase = policy.phase
            status = "Cannot create automatic-session log: \(error.localizedDescription)"
            return
        }
        awakeActivity = ProcessInfo.processInfo.beginActivity(
            options: [.userInitiated, .idleDisplaySleepDisabled],
            reason: "Commercial Breaker automatic commercial detection and AirPlay routing")
        record("Keeping Mac and display awake while automatic mode is active")
        viewingActivity.start()
        viewingActivityFailed = false
        refreshViewingActivity()
        record(playback == .mac ? "Starting local automatic mode · system audio; no session time limit" : "Starting automatic mode · no session time limit; verifying TV playback route")
        recorder.gemini.onConfirmed = { [weak self] state in self?.confirmed(state) }
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkHealth() }
        }
        task = Task {
            do {
                if playback == .mac {
                    try await listen(source: .system, muted: false, id: id)
                    try check(id)
                    policy.startedOnMac(); phase = policy.phase
                    record("Watching on Mac · automatic detection active; sound on")
                    task = nil
                    return
                }
                // Requires TV already selected; arming never silently changes the initial route.
                try await routing.verifyTVForAutomation(tv)
                try check(id)
                try await listen(source: .microphone, muted: false, id: id)
                try check(id)
                policy.startedOnTV(); phase = policy.phase
                record("Watching TV · microphone detection active; waiting for a confirmed break")
                task = nil
            } catch { failed(error, id: id) }
        }
    }

    private func confirmed(_ state: GeminiConfirmation.State) {
        guard enabled, task == nil, pickerRetryAfter == nil else { return }
        let previousPhase = policy.phase
        let action = policy.confirmed(state)
        phase = policy.phase
        let id = generation
        switch action {
        case .none:
            if previousPhase == .awaitingLocalProgram && phase == .watchingMac {
                record("Program confirmed · automatic muting rearmed for the next break")
            }
            return
        case .muteLocal, .unmuteLocal:
            let mute = action == .muteLocal
            do {
                try recorder.setSystemMuted(mute)
                mutedSince = mute ? ProcessInfo.processInfo.systemUptime : nil
                if mute { policy.mutedLocally() } else { policy.unmutedLocally() }
                phase = policy.phase
                record(mute ? "Break confirmed · Mac muted; detection continues" : "Program confirmed · Mac sound restored")
            } catch { failed(error, id: id) }
        case .toMac:
            record("Break confirmed · switching to Mac, then starting muted system capture")
            task = Task {
                do {
                    mayHaveChangedRoute = true
                    try await routing.routeForAutomation(from: tv, to: local)
                    try check(id)
                    recorder.stop(reason: "Automatic break handoff")
                    try await listen(source: .system, muted: true, id: id)
                    try check(id)
                    mutedSince = ProcessInfo.processInfo.systemUptime
                    policy.reachedMac(); phase = policy.phase
                    record("Mac route confirmed · mute requested; system audio now feeds Gemini")
                    task = nil
                } catch { handoffFailed(error, id: id) }
            }
        case .toTV:
            record("Program confirmed · removing mute and returning playback to TV")
            task = Task {
                do {
                    try recorder.setSystemMuted(false)
                    mutedSince = nil
                    recorder.stop(reason: "Preparing microphone before TV handoff")
                    guard recorder.lastStopErrors.isEmpty else {
                        throw RoutingFailure(message: "System capture cleanup failed before TV handoff: " + recorder.lastStopErrors.joined(separator: "; "))
                    }
                    try await listen(source: .microphone, muted: false, id: id)
                    try check(id)
                    record("Microphone ready · requesting TV route with audio setup complete")
                    try await routing.routeForAutomation(from: local, to: tv)
                    try check(id)
                    // Discard Mac-room audio accumulated while the picker was open.
                    // This resets classification only, not the audio device.
                    recorder.gemini.resetContext()
                    policy.reachedTV(); phase = policy.phase
                    record("TV route confirmed · existing microphone capture continues")
                    task = nil
                } catch {
                    guard generation == id, enabled else { return }
                    if let failure = error as? RoutingFailure, failure.retryableBeforeSelection {
                        // No destination was pressed: playback is still on the Mac.
                        // Restore audible system capture for the existing retry policy.
                        recorder.stop(reason: "TV picker unavailable; restoring audible Mac capture")
                        do {
                            guard recorder.lastStopErrors.isEmpty else {
                                throw RoutingFailure(message: "Microphone cleanup failed during TV retry recovery")
                            }
                            try await listen(source: .system, muted: false, id: id)
                            try check(id)
                            handoffFailed(error, id: id)
                        } catch { failed(error, id: id) }
                    } else {
                        failed(error, id: id)
                    }
                }
            }
        }
    }

    private func handoffFailed(_ error: Error, id: UUID) {
        guard generation == id, enabled else { return }
        guard let failure = error as? RoutingFailure, failure.retryableBeforeSelection,
              recorder.running, recorder.ready, recorder.gemini.enabled,
              policy.pickerUnavailable() else {
            failed(error, id: id)
            return
        }
        phase = policy.phase
        mutedSince = nil
        pickerRetryAfter = ProcessInfo.processInfo.systemUptime + 30
        task = nil
        record("Picker unavailable before destination selection · playback left on " +
               (phase == .watchingTV ? "TV" : "Mac with sound on") +
               ". Detection continues; retry eligible in 30 seconds after fresh confirmation")
    }

    private func listen(source: AudioRecorderModel.Source, muted: Bool, id: UUID) async throws {
        try check(id)
        recorder.source = source
        recorder.start(initiallyMuted: muted)
        let until = ProcessInfo.processInfo.systemUptime + 15
        while !recorder.ready {
            try check(id)
            guard recorder.running, ProcessInfo.processInfo.systemUptime < until else {
                throw RoutingFailure(message: "Audio capture could not start: \(recorder.status)")
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        try check(id)
        guard let folder = recorder.folder else { throw RoutingFailure(message: "Capture folder unavailable") }
        recorder.gemini.start(directory: folder, retainProgramAudio: source == .system, sport: sport,
                              returnDetection: source == .system && playback == .airPlay)
        guard recorder.gemini.enabled else { throw RoutingFailure(message: recorder.gemini.status) }
        record("Capture source: \(source.rawValue); session: \(folder.lastPathComponent)")
    }

    private func check(_ id: UUID) throws {
        try Task.checkCancellation()
        guard enabled, generation == id else { throw CancellationError() }
    }

    private func checkHealth() {
        guard enabled else { return }
        refreshViewingActivity()
        let now = ProcessInfo.processInfo.systemUptime
        if let pickerRetryAfter, now >= pickerRetryAfter, task == nil {
            self.pickerRetryAfter = nil
            recorder.gemini.resetContext()
            record("Picker retry ready · waiting for fresh program/break confirmation")
        }
        if task == nil, let mutedSince, now - mutedSince >= 180 {
            if policy.localMuteLimitReached() {
                phase = policy.phase
                do {
                    try recorder.setSystemMuted(false)
                    self.mutedSince = nil
                    recorder.gemini.resetContext()
                    policy.localLimitReleased(); phase = policy.phase
                    record("Three-minute mute limit · sound restored; detection continues. Waiting for confirmed program before muting another break")
                } catch { failed(error, id: generation) }
            } else if phase == .mutedMac {
                do {
                    try recorder.setSystemMuted(false)
                    self.mutedSince = nil
                    recorder.gemini.resetContext()
                    policy.airPlayLimitReleased(); phase = policy.phase
                    record("Three-minute mute limit · Mac sound restored; detection and keep-awake continue. Waiting for confirmed program before returning to TV")
                } catch { failed(error, id: generation) }
            }
            return
        }
        guard task == nil, [.watchingTV, .mutedMac, .watchingMac, .mutedLocalMac, .awaitingLocalProgram, .audibleMacAwaitingTV].contains(phase) else { return }
        if !recorder.running || !recorder.ready || !recorder.gemini.enabled {
            stopAndRecover(reason: "Detection stopped: \(recorder.gemini.status)")
        }
    }

    private func failed(_ error: Error, id: UUID) {
        guard generation == id, enabled else { return }
        task = nil
        stopAndRecover(reason: "Automatic test stopped: \(error.localizedDescription)")
    }

    /// Releases the tap immediately, then waits for any canceled AX action before recovery.
    func stopAndRecover(reason: String = "Stopped by you") {
        guard busy else { return }
        generation = UUID()
        let id = generation
        enabled = false
        releaseAwakeActivity()
        recovering = true
        policy.recover(); phase = policy.phase
        recorder.gemini.onConfirmed = nil
        timer?.invalidate(); timer = nil
        let previous = task
        previous?.cancel()
        recorder.stop(reason: reason)
        mutedSince = nil
        pickerRetryAfter = nil
        let cleanup = recorder.lastStopErrors
        record(cleanup.isEmpty
               ? "\(reason). Capture stopped; " + (mayHaveChangedRoute ? "requesting TV recovery" : "no route change attempted")
               : "\(reason). Audio cleanup reported: \(cleanup.joined(separator: "; ")). Verify sound manually.")
        task = Task {
            await previous?.value
            guard generation == id else { return }
            guard mayHaveChangedRoute else {
                record("Automatic mode off · no playback route change was attempted")
                recovering = false; policy.stop(); phase = policy.phase; task = nil
                return
            }
            do {
                try await routing.routeForAutomation(from: nil, to: tv)
                guard generation == id else { return }
                record("Automatic mode off · TV route confirmed. Verify picture and sound.")
            } catch {
                guard generation == id else { return }
                record("Automatic mode off; capture stopped. TV recovery failed: \(error.localizedDescription). Use Safari's AirPlay picker to recover.")
            }
            recovering = false
            policy.stop(); phase = policy.phase
            task = nil
        }
    }

    /// App termination cannot wait for asynchronous picker control; always remove mute.
    func shutdown() {
        generation = UUID()
        enabled = false; recovering = false
        releaseAwakeActivity()
        pickerRetryAfter = nil
        timer?.invalidate(); timer = nil
        task?.cancel(); task = nil
        recorder.gemini.onConfirmed = nil
        recorder.stop(reason: "App closed; automatic mute removed")
        policy.stop(); phase = policy.phase
    }

    private func releaseAwakeActivity() {
        viewingActivity.stop()
        guard let activity = awakeActivity else { return }
        awakeActivity = nil
        ProcessInfo.processInfo.endActivity(activity)
    }

    private func refreshViewingActivity() {
        // Do not turn a display back on after it has already been put to sleep.
        guard CGDisplayIsAsleep(CGMainDisplayID()) == 0 else { return }
        if let error = viewingActivity.refresh(now: ProcessInfo.processInfo.systemUptime) {
            if !viewingActivityFailed { record("Viewing keep-awake refresh failed (\(error)); screen saver prevention is unavailable") }
            viewingActivityFailed = true
        }
    }

    private func record(_ message: String) {
        status = message
        history = (history.split(separator: "\n").suffix(39).map(String.init)
                   + ["\(Date().formatted(date: .omitted, time: .standard)) · \(message)"]).joined(separator: "\n")
        guard let logURL, var data = try? JSONSerialization.data(withJSONObject: [
            "date": ISO8601DateFormatter().string(from: Date()), "uptime": ProcessInfo.processInfo.systemUptime,
            "message": message, "phase": String(describing: phase)]) else { return }
        data.append(10)
        if !FileManager.default.fileExists(atPath: logURL.path) { FileManager.default.createFile(atPath: logURL.path, contents: nil) }
        do {
            let file = try FileHandle(forWritingTo: logURL)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { status += " · Log write failed" }
    }
}
