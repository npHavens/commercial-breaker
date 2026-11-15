import Foundation
import IOKit

/// Capture and routing calls in the order automatic mode makes them.
@MainActor final class Events { var list: [String] = [] }

@MainActor final class FakeCapture: AutomaticCapture {
    let events: Events
    let root: URL
    var running = false, ready = false, status = "Not listening"
    var folder: URL?
    var lastStopErrors: [String] = []
    var source: AudioRecorderModel.Source = .microphone
    let gemini = GeminiObservation(makeWorker: {
        // Ready at once and never answers: the tests deliver confirmations themselves.
        let child = Process()
        child.executableURL = URL(fileURLWithPath: "/bin/sh")
        child.arguments = ["-c", #"printf '{"ready":true}\n'; exec cat >/dev/null"#]
        return child
    })

    init(events: Events, root: URL) { self.events = events; self.root = root }

    /// Mirrors `AudioRecorderModel`: a running capture or a muted microphone doesn't start.
    func start(initiallyMuted: Bool) {
        guard !running, !initiallyMuted || source == .system else { return }
        let folder = root.appendingPathComponent("recordings/\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        self.folder = folder
        running = true; ready = true
        events.list.append("capture \(source == .system ? "system" : "microphone")\(initiallyMuted ? " muted" : "")")
    }

    func stop(reason: String) {
        gemini.stop()
        running = false; ready = false
        events.list.append("stop capture")
    }

    /// Mirrors `AudioRecorderModel`: only a ready system capture can change the mute.
    func setSystemMuted(_ muted: Bool) throws {
        guard running, ready, source == .system else {
            throw RoutingFailure(message: "System capture is not ready; mute was not changed.")
        }
        events.list.append(muted ? "mute" : "unmute")
    }
}

@MainActor final class FakeRouting: AutomaticRouting {
    let events: Events
    let busy = false, tvName = "Living Room", localName = "Mac"
    /// Thrown by the next routes, in order.
    var failures: [Error] = []
    var holdNext = false
    var held: CheckedContinuation<Void, Never>?

    init(events: Events) { self.events = events }

    func routeForAutomation(from expected: String?, to target: String, retryFocusBounce: Bool) async throws {
        // The focus-bounce retry is only for startup and Stop, never a break or return handoff.
        events.list.append("route \(target == tvName ? "TV" : "Mac")\(retryFocusBounce ? " retry" : "")")
        if holdNext {
            holdNext = false
            await withCheckedContinuation { held = $0 }
        }
        if !failures.isEmpty { throw failures.removeFirst() }
    }
}

@main struct AutomaticModelTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("commercial-breaker-model-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        // Each capture leg starts a real /bin/sh worker, which a loaded CI runner can be slow to run.
        func waitUntil(_ what: String, within seconds: Double = 15, _ condition: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while !condition() {
                precondition(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for \(what)")
                try await Task.sleep(for: .milliseconds(20))
            }
        }
        func makeModel(_ playback: AutomaticCommercialModel.Playback) -> (AutomaticCommercialModel, FakeCapture, FakeRouting, Events) {
            let events = Events()
            let capture = FakeCapture(events: events, root: root), routing = FakeRouting(events: events)
            let model = AutomaticCommercialModel(recorder: capture, routing: routing, logDirectory: root,
                                                 viewingActivity: ViewingActivity(declare: { _ in kIOReturnSuccess }, release: { _ in }))
            model.playback = playback
            return (model, capture, routing, events)
        }
        let returnOrder = ["unmute", "stop capture", "capture microphone", "route TV"]

        // A break moves to the muted Mac, and a confirmed program returns in the required order.
        let (model, capture, routing, events) = makeModel(.airPlay)
        model.start()
        try await waitUntil("watching TV") { model.phase == .watchingTV }
        assert(events.list == ["route TV retry", "capture microphone"], "\(events.list)")
        events.list.removeAll()
        capture.gemini.onConfirmed?(.commercialBreak)
        try await waitUntil("the muted Mac") { model.phase == .mutedMac }
        assert(events.list == ["route Mac", "stop capture", "capture system muted"], "\(events.list)")
        events.list.removeAll()
        capture.gemini.onConfirmed?(.program)
        try await waitUntil("the TV") { model.phase == .watchingTV }
        assert(events.list == returnOrder, "Release the capture and start the microphone before requesting the TV: \(events.list)")
        print("Program return order passed")

        // A silent Mac capture returns in the same order and holds the rest of that break on the TV.
        events.list.removeAll()
        capture.gemini.onConfirmed?(.commercialBreak)
        try await waitUntil("the muted Mac") { model.phase == .mutedMac }
        events.list.removeAll()
        capture.gemini.onSilentAudio?(6)
        try await waitUntil("the TV hold") { model.phase == .awaitingTVProgram }
        assert(events.list == returnOrder, "A silent return must use the program return's order: \(events.list)")
        assert(model.history.contains("Mac capture silent for 6 answers in a row · removing mute and returning playback to TV"))
        events.list.removeAll()
        capture.gemini.onConfirmed?(.commercialBreak)
        try await Task.sleep(for: .milliseconds(200))
        assert(events.list.isEmpty && model.phase == .awaitingTVProgram, "The rest of the break stays on the TV")
        capture.gemini.onConfirmed?(.program)
        assert(model.phase == .watchingTV && model.history.contains("Mac handoff rearmed"), "Program on the TV rearms the next break")
        print("Silent return and same-break hold passed")

        // Nothing else starts while a handoff is in flight. The policy rejects these signals
        // while moving to the Mac, and the model's task guard backs it up.
        routing.holdNext = true
        capture.gemini.onConfirmed?(.commercialBreak)
        try await waitUntil("the held Mac route") { routing.held != nil }
        capture.gemini.onSilentAudio?(6)
        capture.gemini.onConfirmed?(.program)
        try await Task.sleep(for: .milliseconds(200))
        assert(events.list == ["route Mac"] && model.phase == .movingToMac, "\(events.list)")
        routing.held?.resume(); routing.held = nil
        try await waitUntil("the muted Mac") { model.phase == .mutedMac }

        // A silent return whose picker never opens leaves the Mac audible and waits out the retry.
        events.list.removeAll()
        routing.failures = [RoutingFailure(message: "No picker rows", retryableBeforeSelection: true)]
        capture.gemini.onSilentAudio?(6)
        try await waitUntil("the audible Mac") { model.phase == .audibleMacAwaitingTV && events.list.count == 6 }
        assert(events.list == returnOrder + ["stop capture", "capture system"], "\(events.list)")
        assert(model.history.contains("retry eligible in 30 seconds after fresh confirmation or a new silent run"))
        events.list.removeAll()
        capture.gemini.onSilentAudio?(12)
        try await Task.sleep(for: .milliseconds(200))
        assert(events.list.isEmpty && model.phase == .audibleMacAwaitingTV, "No retry before the picker wait ends")
        print("Handoff and picker-retry guards passed")

        // Stop clears both callbacks and returns playback to the TV.
        model.stopAndRecover()
        assert(capture.gemini.onConfirmed == nil && capture.gemini.onSilentAudio == nil, "Stop must disconnect detection")
        try await waitUntil("recovery") { !model.busy }
        assert(events.list == ["stop capture", "route TV retry"], "\(events.list)")
        print("Stop and recovery passed")

        // In Mac playback mode silence only means nothing is playing.
        let (local, localCapture, _, localEvents) = makeModel(.mac)
        local.start()
        try await waitUntil("watching on the Mac") { local.phase == .watchingMac }
        assert(localEvents.list == ["capture system"], "\(localEvents.list)")
        localCapture.gemini.onSilentAudio?(6)
        try await Task.sleep(for: .milliseconds(200))
        assert(localEvents.list == ["capture system"] && local.phase == .watchingMac, "Silence must not move Mac playback")
        local.stopAndRecover()
        try await waitUntil("stop") { !local.busy }
        print("Automatic model checks passed · fake capture and routing; no audio is captured and no AirPlay route changes")
    }
}
