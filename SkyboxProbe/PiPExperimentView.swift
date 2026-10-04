import AVKit
import SwiftUI

struct ContentView: View {
    @StateObject private var log = CaptureProbe()
    @StateObject private var pip = PiPProbe()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                Text("Skybox • PiP background test").font(.title)
                PiPPlayerView(playerLayer: pip.playerLayer).frame(width: 480, height: 270)
                Text(pip.status).lineLimit(2)
                Text("Live heartbeats: \(pip.heartbeatCount) • Successful requests: \(pip.networkCount) • Last gap: \(pip.lastGap, specifier: "%.1f")s")
                    .font(.caption)
                HStack {
                    Button("Prepare video") { pip.prepare() }.disabled(pip.running)
                    Button("Start PiP") { pip.startPiP() }.disabled(!pip.running || !pip.ready || pip.active)
                    Button("Stop test") { pip.stop() }.disabled(!pip.running)
                    NavigationLink("Event log") {
                        List(Array(log.events.reversed().enumerated()), id: \.offset) { _, event in
                            Text(event).font(.system(size: 22, design: .monospaced)).padding(.vertical, 8)
                        }.navigationTitle("Event log — newest first")
                    }
                }
                Text("Start PiP, then open DIRECTV for two minutes. Return and inspect background heartbeats and network results. Test stops after five minutes.")
                    .font(.caption).multilineTextAlignment(.center)
                Text("The clip is prerecorded. Its animation alone does not prove Skybox keeps running.")
                    .font(.caption)
                HStack {
                    Button("Log audio route") { pip.logAudioRoute() }
                    NavigationLink("Earlier capture experiment") { CaptureView(probe: log) }
                }.font(.caption)
                Text("TV/audio-system mute requires a device-specific control path; it is not implemented yet.")
                    .font(.caption2)
            }.padding(40)
        }
        .onAppear { pip.onEvent = { log.recordEvent($0) } }
        .onChange(of: scenePhase) { _, phase in pip.sceneChanged(String(describing: phase)) }
    }
}

private struct PiPPlayerView: UIViewRepresentable {
    let playerLayer: AVPlayerLayer
    func makeUIView(context: Context) -> PlayerSurface { PlayerSurface(playerLayer: playerLayer) }
    func updateUIView(_ uiView: PlayerSurface, context: Context) {}
}

private final class PlayerSurface: UIView {
    let playerLayer: AVPlayerLayer
    init(playerLayer: AVPlayerLayer) {
        self.playerLayer = playerLayer
        super.init(frame: .zero)
        layer.addSublayer(playerLayer)
    }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func layoutSubviews() {
        super.layoutSubviews()
        playerLayer.frame = bounds
    }
}
