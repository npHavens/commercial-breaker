import SwiftUI

struct AutomaticCommercialView: View {
    @ObservedObject var model: AutomaticCommercialModel
    @ObservedObject var recorder: AudioRecorderModel
    @ObservedObject var routing: RoutingModel
    var otherCaptureActive: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Automatic commercial test · v0.2.42").font(.title2.bold())
            Picker("Sport", selection: $model.sport) {
                ForEach(GeminiObservation.Sport.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(model.busy || recorder.running)
            Picker("Playback", selection: $model.playback) {
                ForEach(AutomaticCommercialModel.Playback.allCases, id: \.self) { Text($0.rawValue).tag($0) }
            }.disabled(model.busy || recorder.running)
            Text(model.playback == .mac ? "Confirmed break → mute Mac · confirmed program → restore sound" : "TV → confirmed break → muted Mac → confirmed program → TV")
            Text(model.playback == .mac ? "Keep Paramount+ or DIRECTV playing audibly on the Mac. Leave AirPlay off for this mode. Detection continues through system audio while muted." : "Start with DIRECTV or Paramount+ playing on the TV with the matching Safari tab active. Keep the extension’s Try AirPlay button or the relay’s Choose AirPlay button visible. Safari comes forward during each handoff; leave it alone while the picker is moving.")
                .font(.callout)
            if model.playback == .airPlay {
                Text("TV: \(routing.tvName.isEmpty ? "Set in AirPlay tab" : routing.tvName)\nMac: \(routing.localName)")
                    .font(.callout.monospaced())
            }
            Text(model.playback == .mac
                 ? "Starting sends system-audio samples to Google Vertex AI. All Mac playback audio is captured and muted together; pause other audio. The microphone is not used in this mode."
                 : "Starting sends audio samples, including nearby voices, to Google Vertex AI. It listens through the microphone on TV, then through system audio while the Mac is muted. Other Mac audio is captured and muted too.")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("Start automatic test") { model.start() }
                    .disabled(model.busy || recorder.running || routing.busy || otherCaptureActive)
                Button(model.playback == .mac ? "Stop & restore sound" : "Stop & return to TV") { model.stopAndRecover() }
                    .disabled(!model.enabled)
            }
            if !model.busy && recorder.running {
                Text("Stop the Recorder session first, then start this test.").foregroundStyle(.orange)
            }
            Text(model.status).font(.callout.bold()).textSelection(.enabled)
            AutomaticPredictionView(observer: recorder.gemini)
            HStack {
                Button("Commercial started") { recorder.mark("Commercial started") }
                Button("Program returned") { recorder.mark("Program returned") }
                Button("Changed channel") { recorder.mark("Changed channel") }
            }.disabled(!model.enabled || !recorder.ready)
            Text("Keep using markers if convenient. They record observations and do not trigger muting.")
                .font(.caption).foregroundStyle(.secondary)
            ScrollView { Text(model.history).font(.caption.monospaced()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                .frame(height: 180)
            Text(model.playback == .mac
                 ? "Runs until stopped. After 3 minutes muted, sound returns and detection continues; another break can mute only after program is confirmed. A terminal detector failure stops automation and releases mute. Closing the app releases mute."
                 : "Runs until stopped. A break lasting 3 minutes or a terminal detector failure stops automation, releases mute and attempts TV recovery. Brief Mac audio may be heard during handoffs. Closing the app releases mute but cannot finish AirPlay recovery.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 700)
    }
}

private struct AutomaticPredictionView: View {
    @ObservedObject var observer: GeminiObservation
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(observer.confirmation).font(.headline)
            Text(observer.prediction.isEmpty ? observer.status : "Raw: " + observer.prediction).font(.caption)
        }
    }
}
