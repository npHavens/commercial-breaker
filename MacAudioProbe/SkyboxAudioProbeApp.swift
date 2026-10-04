import SwiftUI
import AppKit

@main
struct SkyboxAudioProbeApp: App {
    @NSApplicationDelegateAdaptor(ProbeAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Skybox Audio Probe") {
            ProbeTabs(audio: delegate.model, routing: delegate.routing, video: delegate.video, recorder: delegate.recorder, automatic: delegate.automatic)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    let model = ProbeModel()
    let video = VideoProbe()
    let recorder = AudioRecorderModel()
    lazy var routing = RoutingModel(audio: model)

    lazy var automatic = AutomaticCommercialModel(recorder: recorder, routing: routing)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        automatic.shutdown()
        routing.cancel()
        model.stop(reason: "App closed")
        video.stop()
        recorder.stop(reason: "App closed")
    }
}

private struct ProbeTabs: View {
    @ObservedObject var audio: ProbeModel
    @ObservedObject var routing: RoutingModel
    @ObservedObject var video: VideoProbe
    @ObservedObject var recorder: AudioRecorderModel
    @ObservedObject var automatic: AutomaticCommercialModel

    var body: some View {
        TabView {
            AutomaticCommercialView(model: automatic, recorder: recorder, routing: routing,
                                    otherCaptureActive: audio.running || video.phase != .idle)
                .tabItem { Label("Automatic", systemImage: "speaker.wave.2") }
            AudioRecorderView(model: recorder, otherCaptureActive: audio.running || routing.busy).disabled(automatic.busy)
                .tabItem { Label("Recorder", systemImage: "record.circle") }
            ProbeView(model: audio).disabled(recorder.running || automatic.busy)
                .tabItem { Label("Audio", systemImage: "waveform") }
            RoutingView(model: routing).disabled(recorder.running || automatic.busy)
                .tabItem { Label("AirPlay", systemImage: "airplayvideo") }
            VideoProbeView(model: video).disabled(automatic.busy).tabItem { Label("Video", systemImage: "video") }
        }.padding(8)
    }
}

private struct VideoProbeView: View {
    @ObservedObject var model: VideoProbe

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Native Video Capture").font(.title2.bold())
            Text("First try an ordinary window, then DIRECTV. Seeing browser controls around black video does not count as capturing the broadcast.")
                .foregroundStyle(.secondary)
            HStack {
                Button("Choose window") { model.choose(display: false) }.disabled(model.phase != .idle)
                Button("Choose display") { model.choose(display: true) }.disabled(model.phase != .idle)
                Button("Stop") { model.stop() }.disabled(model.phase == .idle || model.phase == .stopping)
            }
            Text(model.status).textSelection(.enabled)
            ZStack {
                Color.black
                if let image = model.preview {
                    Image(nsImage: image).resizable().scaledToFit()
                } else { Text("Waiting for a captured frame").foregroundStyle(.white) }
            }.frame(height: 290)
            HStack {
                Text("Captured frames: \(model.frameCount)")
                if let date = model.lastFrameAt { Text("Last frame: \(date.formatted(date: .omitted, time: .standard))") }
            }.font(.caption.monospacedDigit())
            Text("Stops after two minutes. First and latest JPEG frames save automatically for inspection.")
                .font(.caption)
            if let folder = model.folder {
                Button("Show saved frames") { NSWorkspace.shared.open(folder) }
                Text(folder.path).font(.caption).textSelection(.enabled)
            }
        }.padding(24).frame(width: 600)
    }
}

private struct ProbeView: View {
    @ObservedObject var model: ProbeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Skybox · System Audio Probe").font(.title2.bold())
            Text("Measures all Mac playback audio. Pause other audio to isolate DIRECTV. No microphone or audio recording is used.")
                .foregroundStyle(.secondary)
            Picker("Test label", selection: $model.source) {
                Text("Unprotected control").tag("Unprotected control")
                Text("DIRECTV · Safari local").tag("DIRECTV local")
                Text("DIRECTV · native AirPlay").tag("DIRECTV AirPlay")
            }.disabled(model.running)

            Text(model.status).font(.headline).textSelection(.enabled).frame(minHeight: 44, alignment: .leading)
            ProgressView(value: meterValue, total: 1)
            HStack {
                Text("Peak: \(decibels(model.peak))")
                Text("RMS: \(decibels(model.rms))")
            }.monospacedDigit()
            Text("\(model.callbacks) callbacks · \(model.samples) samples")
                .font(.caption.monospacedDigit())

            HStack {
                Button("Start capture") { model.start() }.disabled(model.running)
                Button("Stop") { model.stop() }.disabled(!model.running)
                Spacer()
                if model.running { Text("Auto-stop: \(model.secondsRemaining)s").monospacedDigit() }
            }
            Divider()
            Text("Mute test affects all captured Mac audio for ten seconds. Capture should continue; listen to confirm output is quiet.")
                .font(.callout)
            HStack {
                Button("Mute Mac audio for 10s") { model.muteForTenSeconds() }
                    .disabled(!model.running || model.muted)
                Button("Restore output now") { model.restoreOutput() }
                    .disabled(!model.muted)
                if model.muted { Text("\(model.muteSecondsRemaining)s").monospacedDigit() }
            }
            Divider()
            Text("Level measurements save automatically; raw audio is never saved.").font(.caption)
            Text(model.logPath).font(.caption).textSelection(.enabled)
            if let error = model.logError { Text(error).foregroundStyle(.red).textSelection(.enabled) }
            Button("Show diagnostic files") { model.showLogs() }
            Text("v0.2.12 · Capture feasibility only; no commercial detection yet.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(24)
        .frame(width: 600)
    }

    private var meterValue: Double {
        guard model.peak > 0 else { return 0 }
        return min(1, max(0, (20 * log10(model.peak) + 80) / 80))
    }

    private func decibels(_ value: Double) -> String {
        value > 0 ? String(format: "%.1f dBFS", 20 * log10(value)) : "−∞ dBFS"
    }
}
