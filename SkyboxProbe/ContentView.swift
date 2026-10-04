import SwiftUI

struct CaptureView: View {
    @ObservedObject var probe: CaptureProbe
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Text("Project Skybox • Capture Probe").font(.title)
                Text("ScreenCaptureKit • Window capture experiment")
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    VStack {
                        Text(context.date.formatted(date: .omitted, time: .standard))
                            .font(.system(size: 44, design: .monospaced))
                        if let saved = probe.lastFrameAt {
                            Text("Last saved frame: \(Int(max(0, context.date.timeIntervalSince(saved)))) seconds ago")
                                .font(.caption)
                        }
                    }
                }
                Text(probe.status).lineLimit(3)
                HStack {
                    Button("Choose window") { probe.start() }.disabled(probe.phase != .idle)
                    Button("Stop capture") { probe.stop() }.disabled(probe.phase != .capturing)
                    NavigationLink("Frames (\(probe.frames.count))") { frameList }
                    NavigationLink("Event log") { eventList }
                }
                Text("Inspect the window picker. Capture here for 60 seconds, then switch apps for 60 seconds. Compare saved images and timestamps.")
                    .font(.caption).multilineTextAlignment(.center)
                if let frame = probe.frames.first, let image = UIImage(contentsOfFile: frame.url.path) {
                    Image(uiImage: image).resizable().scaledToFit().frame(height: 220)
                }
                Text(probe.events.last ?? "").font(.caption2).lineLimit(2)
            }
            .padding(45)
        }
        .onChange(of: scenePhase) { _, phase in
            probe.recordEvent("Scene: \(phase)")
        }
    }

    private var frameList: some View {
        List(probe.frames) { frame in
            NavigationLink {
                VStack {
                    Text(frame.savedAt.formatted(date: .abbreviated, time: .standard))
                    if let image = UIImage(contentsOfFile: frame.url.path) {
                        Image(uiImage: image).resizable().scaledToFit()
                    } else { Text("Frame no longer available in cache") }
                }.padding(40)
            } label: {
                Text(frame.savedAt.formatted(date: .abbreviated, time: .standard))
            }
        }.navigationTitle("Saved frames — newest first")
    }

    private var eventList: some View {
        List(Array(probe.events.reversed().enumerated()), id: \.offset) { _, event in
            Text(event).font(.system(size: 22, design: .monospaced)).padding(.vertical, 8)
        }.navigationTitle("Event log — newest first")
    }
}
