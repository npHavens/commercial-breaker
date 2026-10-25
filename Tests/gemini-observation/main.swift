import Foundation

@main struct ObservationTests {
    @MainActor static func main() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("skybox-observation-\(UUID())")
        let directory = root.appendingPathComponent("recordings/session")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let script = directory.appendingPathComponent("fake.py")
        try """
        import json, sys, time
        print(json.dumps({'ready':True}), flush=True)
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
        observer.start(directory: directory)
        feed()
        try await Task.sleep(for: .milliseconds(600))
        observer.resetContext()
        try await Task.sleep(for: .milliseconds(1700))
        assert(observer.prediction.isEmpty, "Old-game prediction must be discarded")
        let log = try String(contentsOf: directory.appendingPathComponent("gemini-observations.jsonl"), encoding: .utf8)
        assert(log.contains("discarded-stale-response"), "Test must exercise a response across reset")
        observer.stop()
        observer.start(directory: directory, retainProgramAudio: true)
        feed()
        try await Task.sleep(for: .milliseconds(2600))
        assert(observer.prediction.contains("Program"), "Current context should display prediction")
        assert(observer.confirmation.contains("1/2"), "One prediction cannot confirm program")
        let samples = root.appendingPathComponent("return-audio-diagnostics")
        let wav = try Data(contentsOf: samples.appendingPathComponent("sample-0.wav"))
        assert(wav.count == 256044 && String(data: wav.prefix(4), encoding: .ascii) == "RIFF")
        let saved = try JSONSerialization.jsonObject(with: Data(contentsOf: samples.appendingPathComponent("sample-0.json"))) as! [String: Any]
        assert(saved["session"] as? String == "session")
        try await Task.sleep(for: .milliseconds(2800))
        feed()
        try await Task.sleep(for: .milliseconds(2100))
        assert(observer.confirmation.hasPrefix("Confirmed: Program"), "Two recent predictions should confirm program")
        let rapidLog = try String(contentsOf: directory.appendingPathComponent("gemini-observations.jsonl"), encoding: .utf8)
        let requests = rapidLog.split(separator: "\n").compactMap { line -> [String: Any]? in
            guard let data = line.data(using: .utf8), let value = try? JSONSerialization.jsonObject(with: data) as? [String: Any], value["event"] as? String == "request" else { return nil }
            return value
        }
        let lastTwo = Array(requests.suffix(2))
        let spacing = (lastTwo[1]["uptime"] as! Double) - (lastTwo[0]["uptime"] as! Double)
        assert(spacing >= 5 && lastTwo[1]["fastFollowUp"] as? Bool == false, "Program confirmation must use regular cadence")
        assert((lastTwo[1]["endUptime"] as! Double) - (lastTwo[0]["endUptime"] as! Double) >= 5, "Program confirmation must use five fresh seconds")
        observer.stop()
        assert(!observer.enabled && observer.prediction.isEmpty)
        try await Task.sleep(for: .milliseconds(300))
        assert(!observer.enabled && observer.prediction.isEmpty, "Stop must suppress late callbacks")
        try """
        import json, sys
        print(json.dumps({'ready':True}), flush=True)
        for i,line in enumerate(sys.stdin):
            request=json.loads(line)
            if i==0:
                print(json.dumps({'id':request['id'],'error':'request-failed'}), flush=True)
            else:
                print(json.dumps({'id':request['id'],'result':{'state_at_end':'program'},'elapsedMs':1,'usage':{}}), flush=True)
        """.write(to: script, atomically: true, encoding: .utf8)
        observer.start(directory: directory)
        feed()
        try await Task.sleep(for: .milliseconds(2200))
        assert(observer.enabled && observer.status.contains("checking fresh audio"), "Isolated unclassified failure should recover without disabling")
        assert(observer.prediction.isEmpty, "Failure must clear old prediction")
        assert(observer.confirmation == "Waiting for two matching predictions")
        try await Task.sleep(for: .milliseconds(3500))
        feed()
        try await Task.sleep(for: .milliseconds(1800))
        assert(observer.enabled && observer.prediction.contains("Program"), "Fresh sample after unclassified failure should restore observation")
        observer.stop()
        for (error, hint) in [("configuration-missing", "GOOGLE_CLOUD_PROJECT"), ("dependencies-missing", "npm ci"), ("app-rebuild-required", "rebuild the app"), ("/private/path", "README")] {
            try """
            import json, sys
            print(json.dumps({'ready':False,'error':'\(error)'}), flush=True)
            sys.stdin.read()
            """.write(to: script, atomically: true, encoding: .utf8)
            observer.start(directory: directory)
            try await Task.sleep(for: .milliseconds(500))
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
