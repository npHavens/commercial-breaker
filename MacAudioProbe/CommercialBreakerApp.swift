import SwiftUI
import AppKit

@main
struct CommercialBreakerApp: App {
    @NSApplicationDelegateAdaptor(ProbeAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup("Commercial Breaker") {
            ProbeTabs(routing: delegate.routing, recorder: delegate.recorder, automatic: delegate.automatic)
        }
        .windowResizability(.contentSize)
    }
}

@MainActor
final class ProbeAppDelegate: NSObject, NSApplicationDelegate {
    let recorder: AudioRecorderModel
    let routing: RoutingModel

    override init() {
        migrateUserApplicationSupportDirectory()
        recorder = AudioRecorderModel()
        routing = RoutingModel()
        super.init()
    }

    lazy var automatic = AutomaticCommercialModel(recorder: recorder, routing: routing)

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { true }
    func applicationWillTerminate(_ notification: Notification) {
        automatic.shutdown()
        routing.cancel()
        recorder.stop(reason: "App closed")
    }
}

private struct ProbeTabs: View {
    @ObservedObject var routing: RoutingModel
    @ObservedObject var recorder: AudioRecorderModel
    @ObservedObject var automatic: AutomaticCommercialModel

    var body: some View {
        TabView {
            AutomaticCommercialView(model: automatic, recorder: recorder, routing: routing)
                .tabItem { Label("Automatic", systemImage: "speaker.wave.2") }
            RoutingView(model: routing).disabled(recorder.running || automatic.busy)
                .tabItem { Label("AirPlay", systemImage: "airplayvideo") }
        }.padding(8)
    }
}
