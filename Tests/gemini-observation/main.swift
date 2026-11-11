import Foundation

@main struct ObservationTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("commercial-breaker-observation-\(UUID())")
        let directory = root.appendingPathComponent("recordings/session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = directory.appendingPathComponent("fake.py")
        try """
        import json, sys, time
        print(json.dumps({'ready':True,'promptSHA256':'0'*64,'model':'fake-model'}), flush=True)
        for line in sys.stdin:
            request=json.loads(line)
            time.sleep(1)
            print(json.dumps({'id':request['id'],'result':{'state_at_end':'program'},'elapsedMs':1000,'usage':{}}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let observer = GeminiObservation(makeWorker: {
            let child = Process()
            child.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            child.arguments = [script.path]
            return child
        })
        func feed() {
            let end = ProcessInfo.processInfo.systemUptime
            for n in 0..<8 {
                observer.buffer.ingest(Array(repeating: Float(0.1), count: 16000), sampleRate: 16000, endedAt: end - 7 + Double(n))
            }
        }
        // Wait on logged events rather than fixed delays: a loaded CI runner can take
        // seconds to start python3 or deliver a response.
        func waitUntil(_ what: String, within seconds: Double = 15, _ condition: () -> Bool) async throws {
            let deadline = ProcessInfo.processInfo.systemUptime + seconds
            while !condition() {
                precondition(ProcessInfo.processInfo.systemUptime < deadline, "Timed out waiting for \(what)")
                try await Task.sleep(for: .milliseconds(50))
            }
        }
        let logURL = directory.appendingPathComponent("gemini-observations.jsonl")
        func events(_ name: String) -> [[String: Any]] {
            ((try? String(contentsOf: logURL, encoding: .utf8)) ?? "").split(separator: "\n").compactMap { line in
                guard let value = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                      value["event"] as? String == name else { return nil }
                return value
            }
        }
        func uptime(_ event: [String: Any]?) -> Double { event?["uptime"] as! Double }
        // Audio counts as recent for only two seconds, so feed it once the worker is ready.
        func startAndAwaitRequest(retainProgramAudio: Bool = false) async throws {
            let ready = events("worker-ready").count, sent = events("request").count
            observer.start(directory: directory, retainProgramAudio: retainProgramAudio)
            try await waitUntil("the fake worker to start") { events("worker-ready").count > ready }
            feed()
            try await waitUntil("the fake worker to take a request") { events("request").count > sent }
        }
        try await startAndAwaitRequest()
        observer.resetContext()
        try await waitUntil("a response across the reset") { !events("discarded-stale-response").isEmpty }
        assert(observer.prediction.isEmpty, "Old-game prediction must be discarded")
        let ready = events("worker-ready").last
        assert(ready?["model"] as? String == "fake-model", "worker-ready must record the model the worker reports")
        assert(ready?["promptSHA256"] as? String == String(repeating: "0", count: 64), "worker-ready must record a valid prompt hash")
        observer.stop()
        try await startAndAwaitRequest(retainProgramAudio: true)
        let predicted = events("prediction").count
        try await waitUntil("the first prediction") { events("prediction").count > predicted }
        assert(observer.prediction.contains("Program"), "Current context should display prediction")
        assert(observer.confirmation.contains("1/2"), "One prediction cannot confirm program")
        let samples = root.appendingPathComponent("return-audio-diagnostics")
        let wav = try Data(contentsOf: samples.appendingPathComponent("sample-0.wav"))
        assert(wav.count == 256044 && String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: samples.appendingPathComponent("sample-0.json"))) as! [String: Any]
        assert(saved["session"] as? String == "session")
        // Feed once the regular five-second interval has passed, so the audio is fresh when it is sent.
        let firstSent = uptime(events("request").last)
        try await waitUntil("the regular interval") { ProcessInfo.processInfo.systemUptime >= firstSent + 5 }
        feed()
        try await waitUntil("the second prediction") { events("prediction").count > predicted + 1 }
        assert(observer.confirmation.hasPrefix("Confirmed: Program"), "Two recent predictions should confirm program")
        let lastTwo = Array(events("request").suffix(2))
        let spacing = (lastTwo[1]["uptime"] as! Double) - (lastTwo[0]["uptime"] as! Double)
        assert(spacing >= 5 && lastTwo[1]["fastFollowUp"] as? Bool == false, "Program confirmation must use regular cadence")
        assert((lastTwo[1]["endUptime"] as! Double) - (lastTwo[0]["endUptime"] as! Double) >= 5, "Program confirmation must use five fresh seconds")
        observer.stop()
        assert(!observer.enabled && observer.prediction.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        assert(!observer.enabled && observer.prediction.isEmpty, "Stop must suppress late callbacks")
        try """
        import json, sys
        print(json.dumps({'ready':True,'promptSHA256':'0'*64}), flush=True)
        for i,line in enumerate(sys.stdin):
            request=json.loads(line)
            if i==0:
                print(json.dumps({'id':request['id'],'error':'request-failed'}), flush=True)
            elif i==1:
                print(json.dumps({'id':request['id'],'result':{'state_at_end':'unusable'},'elapsedMs':0,'usage':{},'source':'local-digital-silence'}), flush=True)
            elif i==2:
                print(json.dumps({'id':request['id'],'error':'timeout'}), flush=True)
            else:
                print(json.dumps({'id':request['id'],'result':{'state_at_end':'program'},'elapsedMs':1,'usage':{}}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let recoveries = events("request-recovery").count
        try await startAndAwaitRequest()
        assert(events("worker-ready").last?["model"] as? String == "unreported", "A ready line without a model must say so")
        try await waitUntil("recovery from the failed request") { events("request-recovery").count > recoveries }
        assert(observer.enabled && observer.status.contains("checking fresh audio"), "Isolated unclassified failure should recover without disabling")
        assert(observer.prediction.isEmpty, "Failure must clear old prediction")
        assert(observer.confirmation == "Waiting for two matching predictions")
        assert(events("request-recovery").last?["failingSeconds"] is NSNumber, "Recovery must log how long the streak has been failing")
        // The recovery delay starts when the failure arrives; feed once it has passed.
        func awaitRecoveryDelay() async throws {
            let recovery = events("request-recovery").last
            let resumeAt = uptime(recovery) + (recovery?["delaySeconds"] as! NSNumber).doubleValue
            try await waitUntil("the recovery delay") { ProcessInfo.processInfo.systemUptime >= resumeAt }
        }
        try await awaitRecoveryDelay()
        let silent = events("prediction").count
        feed()
        try await waitUntil("the worker's local silence answer") { events("prediction").count > silent }
        assert(observer.status.hasPrefix("Audio is silent"), "A silence answer mid-streak must not report Gemini as healthy")
        // The worker answers digital silence without Gemini, so the next failure continues the streak.
        let silenceSent = uptime(events("request").last)
        try await waitUntil("the regular interval") { ProcessInfo.processInfo.systemUptime >= silenceSent + 5 }
        feed()
        try await waitUntil("the second failure") { events("request-recovery").count > recoveries + 1 }
        assert(events("request-recovery").last?["consecutiveFailures"] as? Int == 2, "A local silence answer must not reset the failure streak")
        assert(observer.enabled && observer.status.contains("checking fresh audio"), "A timeout after an unclassified failure keeps recovering")
        try await awaitRecoveryDelay()
        let recovered = events("prediction").count
        feed()
        try await waitUntil("a prediction after recovery") { events("prediction").count > recovered }
        assert(observer.enabled && observer.prediction.contains("Program"), "Fresh sample after the failures should restore observation")
        observer.stop()
        // Readiness does not depend on the reported values, and malformed ones are never logged.
        try """
        import json, sys
        print(json.dumps({'ready':True,'promptSHA256':'A'*64,'model':'not a model'}), flush=True)
        for line in sys.stdin:
            print(json.dumps({'id':json.loads(line)['id'],'result':{'state_at_end':'program'},'elapsedMs':1,'usage':{}}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        try await startAndAwaitRequest()
        let malformed = events("worker-ready").last
        assert(malformed?["promptSHA256"] == nil, "A prompt hash that is not lowercase hex must not be logged")
        assert(malformed?["model"] as? String == "invalid", "A malformed model must not be logged")
        observer.stop()
        // A session started with a failures-in-a-row limit (AirPlay's Mac leg) stops at it.
        try """
        import json, sys
        print(json.dumps({'ready':True,'promptSHA256':'0'*64}), flush=True)
        for line in sys.stdin:
            print(json.dumps({'id':json.loads(line)['id'],'error':'timeout'}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        let limitedReady = events("worker-ready").count
        observer.start(directory: directory, failuresInARowLimit: 1)
        try await waitUntil("the fake worker to start") { events("worker-ready").count > limitedReady }
        feed()
        try await waitUntil("the stop at the failure limit") { !observer.enabled }
        assert(observer.status.contains("1 failed request in a row"), "The limit must stop Gemini and say why")
        let zeros = String(repeating: "0", count: 64)
        for (hash, valid) in [(zeros, true), (String(repeating: "A", count: 64), false), (String(zeros.dropLast()) + "\u{FF10}", false), (zeros + "0", false)] {
            assert(GeminiObservation.isPromptHash(hash) == valid, "\(hash) must \(valid ? "" : "not ")be logged as a prompt hash")
        }
        let longest = String(repeating: "a", count: 128)
        for (reported, logged) in [("publishers/google/models/gemini-3.7-flash@001", "publishers/google/models/gemini-3.7-flash@001"), (longest, longest),
                                   (longest + "a", "invalid"), ("", "invalid"), (37, "invalid"), (NSNull(), "invalid")] as [(Any, String)] {
            assert(GeminiObservation.loggedModel(reported) == logged, "\(reported) must be logged as \(logged)")
        }
        for (error, hint) in [("configuration-missing", "GOOGLE_CLOUD_PROJECT"), ("dependencies-missing", "npm ci"), ("app-rebuild-required", "rebuild the app"), ("/private/path", "README")] {
            try """
            import json, sys
            print(json.dumps({'ready':False,'error':'\(error)'}), flush=True)
            sys.stdin.read()
            """.write(to: script, atomically: true, encoding: .utf8)
            observer.start(directory: directory)
            // Well under the 20-second startup timeout, so only the reported failure can stop it.
            try await waitUntil("the setup failure", within: 5) { !observer.enabled }
            assert(!observer.enabled && observer.status.contains(hint), "Setup failure should name its fix")
            assert(!observer.status.contains("/private"), "Unrecognized setup errors must not be displayed")
        }
        for (sport, returnDetection, name, flag) in [(GeminiObservation.Sport.football, false, "football", "0"), (.ufc, true, "ufc", "1")] {
            let environment = GeminiObservation.workerEnvironment(["PATH": "/usr/bin"], sport: sport, returnDetection: returnDetection)
            assert(environment["COMMERCIAL_BREAKER_SPORT"] == name && environment["COMMERCIAL_BREAKER_RETURN_DETECTION"] == flag, "Worker environment must carry the sport and return detection")
            assert(environment["SKYBOX_SPORT"] == nil && environment["SKYBOX_RETURN_DETECTION"] == nil, "Worker environment must not carry the legacy names")
            assert(environment["PATH"] == "/usr/bin", "Worker environment must keep the inherited settings")
        }
        print("Gemini lifecycle, fresh-audio failure recovery and setup failures passed · fake worker only, no upload")
    }
}
