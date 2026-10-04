import SwiftUI
import AppKit

struct AudioRecorderView: View {
    @ObservedObject var model: AudioRecorderModel
    var otherCaptureActive: Bool

    var body: some View {
        ScrollView {
        VStack(alignment: .leading, spacing: 14) {
            Text("Sports Audio Recorder · v0.2.41").font(.title2.bold())
            Text("Collect examples across any network. Save marked clips and compare experimental predictions. Playback stays manual.")
                .foregroundStyle(.secondary)
            Picker("Listen using", selection: $model.source) {
                ForEach(AudioRecorderModel.Source.allCases, id: \.self) { source in
                    Text(source.rawValue).tag(source)
                }
            }.disabled(model.running)
            Text(model.source == .microphone
                 ? "The Mac microphone must hear the TV. Marked clips may include nearby conversation."
                 : "Records all Mac playback audio. Pause other audio, and stop recording before changing the AirPlay route.")
                .font(.callout)
            HStack {
                Button("Start listening") { model.start() }.disabled(model.running || otherCaptureActive)
                Button("Stop & save") { model.stop() }.disabled(!model.running)
                Spacer()
                Text(model.secondsRemaining.map { "\($0)s remaining" } ?? "No recording time limit").monospacedDigit()
            }
            if otherCaptureActive { Text("Stop the Audio or AirPlay test first.").foregroundStyle(.orange) }
            ProgressView(value: min(1, max(0, (20 * log10(max(model.rms, 0.000001)) + 60) / 60)))
            Text(model.rms > 0 ? String(format: "Input RMS: %.1f dBFS", 20 * log10(model.rms)) : "Waiting for audible input")
                .font(.caption.monospacedDigit())
            VStack(alignment: .leading, spacing: 6) {
                Text(model.cueStatus).font(.caption)
                HStack(spacing: 20) {
                    cueMeter("Speech", value: model.cues?.speech)
                    cueMeter("Music", value: model.cues?.music)
                    cueMeter("Crowd / cheering", value: model.cues?.crowd)
                }
                Text("\(model.markedContext). Scores describe sounds, not whether an ad is playing.")
                    .font(.caption).foregroundStyle(.secondary)
                if let date = model.lastCandidateAt {
                    Text("Possible break cue at \(date.formatted(date: .omitted, time: .standard)) · playback unchanged")
                        .font(.callout).foregroundStyle(.orange)
                }
                Text("Transition cues this session: \(model.candidateCount) · keep using your normal markers to check them.")
                    .font(.caption)
            }
            GeminiObservationView(observer: model.gemini, ready: model.ready, directory: model.folder)
            HStack {
                Button("Commercial started") { model.mark("Commercial started") }
                Button("Program returned") { model.mark("Program returned") }
                Button("Changed channel") { model.mark("Changed channel") }
            }.disabled(!model.ready)
            Text("Each break marker saves up to 20 seconds before and 10 seconds after your click. A late click is fine. Mark channel changes to keep examples separate.")
                .font(.caption)
            Text(model.status).textSelection(.enabled)
            ScrollView { Text(model.history).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(height: 125)
            Text("Sound scores are logged throughout the session. Audio is saved only around your markers. Gemini sends samples only while explicitly enabled. Auto-stops after 15 minutes.").font(.caption)
            if let folder = model.folder {
                Button("Show saved clips") { NSWorkspace.shared.open(folder) }
                Text(folder.path).font(.caption).textSelection(.enabled)
            }
        }.padding(24)
        }.frame(width: 700, height: min(800, (NSScreen.main?.visibleFrame.height ?? 900) - 100))
    }

    private func cueMeter(_ title: String, value: Double?) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title).font(.caption)
            ProgressView(value: value ?? 0, total: 1)
            Text(value.map { String(format: "%.2f", $0) } ?? "—")
                .font(.caption.monospacedDigit())
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct GeminiObservationView: View {
    @ObservedObject var observer: GeminiObservation
    let ready: Bool
    let directory: URL?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Gemini · experimental observation").font(.headline)
            Text("When enabled, sends the latest 8 seconds of audio every 5 seconds, faster while confirming a change to Google Vertex AI, including any nearby voices. Stops with recording; does not mute or switch playback.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start Gemini · send audio") {
                    if let directory { observer.start(directory: directory) }
                }.disabled(!ready || observer.enabled)
                Button("Stop Gemini") { observer.stop() }.disabled(!observer.enabled)
            }
            Text(observer.status).font(.caption)
            Text(observer.confirmation).font(.callout.bold())
            if !observer.prediction.isEmpty {
                Text("Raw: " + observer.prediction).font(.caption).textSelection(.enabled)
            }
        }
    }
}
