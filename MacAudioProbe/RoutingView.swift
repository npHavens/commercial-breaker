import SwiftUI

struct RoutingView: View {
    @ObservedObject var model: RoutingModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("AirPlay setup").font(.title2.bold())
            Text("Keep the streaming tab and Skybox’s Try AirPlay or relay Choose AirPlay button visible in Safari. Inspecting or selecting brings Safari forward; avoid typing or changing apps while it runs.")
            HStack {
                Button("Enable Accessibility") { model.requestPermission() }.disabled(model.busy)
                Button("Inspect picker") { model.inspect() }.disabled(model.busy)
            }
            TextField("Mac's exact picker label", text: $model.localName).disabled(model.busy)
            TextField("Apple TV's exact picker label", text: $model.tvName).disabled(model.busy)
            HStack {
                Button("Select TV / recover") { model.selectTV() }.disabled(model.busy)
                Button("Cancel") { model.cancel() }.disabled(!model.busy)
            }
            Text(model.status).font(.headline).textSelection(.enabled)
            ScrollView {
                Text(model.history.isEmpty ? "Picker inspection and routing events will appear here." : model.history)
                    .font(.system(.caption, design: .monospaced))
                    .frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled)
            }.frame(height: 220)
            if let error = model.logError { Text(error).foregroundStyle(.red) }
            Text("Automatic uses these exact picker labels. Logs save automatically. This tab controls Safari’s page picker; it does not supply a different video player or repair Paramount stream compatibility.")
                .font(.caption).foregroundStyle(.secondary)
        }.padding(24).frame(width: 600)
    }
}
