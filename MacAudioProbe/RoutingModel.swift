import AppKit
import ApplicationServices
import Combine

@MainActor
final class RoutingModel: ObservableObject {
    @Published var localName = UserDefaults.standard.string(forKey: "route.localName") ?? "This Computer" {
        didSet { UserDefaults.standard.set(localName, forKey: "route.localName") }
    }
    @Published var tvName = UserDefaults.standard.string(forKey: "route.tvName") ?? "" {
        didSet { UserDefaults.standard.set(tvName, forKey: "route.tvName") }
    }
    @Published var busy = false
    @Published var status = "Open the Commercial Breaker extension panel or HLS relay player in Safari, then inspect the picker."
    @Published var controls: [RouteControl] = []
    @Published var history = ""
    @Published var logError: String?
    private let accessibility = SafariAccessibility()
    private var task: Task<Void, Never>?
    private var logURL: URL?
    private static let logDirectory = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent(applicationSupportDirectoryName, isDirectory: true)

    func requestPermission() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        let granted = AXIsProcessTrustedWithOptions(options)
        status = granted ? "Accessibility permission is enabled." : "Enable SkyboxAudioProbe in Privacy & Security → Accessibility, then retry."
    }

    func inspect() {
        run {
            let pid = try await self.prepareSafari()
            self.controls = try await self.availablePickerControls(pid: pid, requiredNames: [])
            for note in await self.accessibility.diagnostics() { self.record(note) }
            guard !self.controls.isEmpty else {
                throw RoutingFailure(message: "No pressable controls found in Safari's picker. Its Accessibility structure may differ or belong to another process. No destination was selected.")
            }
            for control in self.controls {
                self.record("\(control.role) · \(control.name) · enabled=\(control.enabled) · selected=\(control.selected.map(String.init) ?? "unknown")")
            }
            self.record("Inspection finished. Enter the exact Mac and TV labels. The picker may close when returning to this app.")
        }
    }

    func selectTV() {
        let name = tvName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { status = "Enter the TV's exact picker label first."; return }
        run {
            let pid = try await self.prepareSafari()
            let initial = try await self.availablePickerControls(pid: pid, requiredNames: [name])
            if initial.filter({ $0.name == name && $0.selected == true }).count == 1 {
                self.record("TV already selected in picker. Confirm picture and sound on the TV.")
                return
            }
            try await self.accessibility.choose(named: name, pid: pid)
            self.record("TV selection requested. Confirm picture and sound on the TV.")
        }
    }

    /// Startup only verifies an existing route. Retry once if opening the picker
    /// returns focus to our own window; never retry a destination selection.
    func verifyTVForAutomation(_ tv: String) async throws {
        do {
            try await routeForAutomation(from: tv, to: tv)
        } catch let failure as RoutingFailure where failure.focusReturnedToCommercialBreaker {
            try await wait(0.5)
            try Task.checkCancellation()
            guard NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier else {
                throw failure
            }
            try await routeForAutomation(from: tv, to: tv)
            record("Startup route verified after one retry for focus returning to Commercial Breaker.")
        }
    }

    /// The caller owns this task and cancellation. Picker selection is verified;
    /// it does not establish that the destination is actually producing sound.
    func routeForAutomation(from expected: String?, to target: String) async throws {
        try Task.checkCancellation()
        guard !busy else {
            throw RoutingFailure(message: "Another routing operation is already running.")
        }
        let destination = target.trimmingCharacters(in: .whitespacesAndNewlines)
        let source = expected?.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !destination.isEmpty, source == nil || source?.isEmpty == false else {
            throw RoutingFailure(message: "Enter exact, nonempty AirPlay route labels before enabling automation.")
        }
        busy = true
        beginLog()
        defer { busy = false }
        var selectionAttempted = false
        do {
            let pid = try await prepareSafari()
            let initial = try await availablePickerControls(pid: pid, requiredNames: [source, destination].compactMap { $0 })
            if let source {
                guard initial.filter({ $0.name == source && $0.selected == true }).count == 1 else {
                    throw RoutingFailure(message: "Expected route ‘\(source)’ is not uniquely selected. Automatic routing stopped without selecting a destination.")
                }
            }
            if initial.filter({ $0.name == destination && $0.selected == true }).count == 1 {
                record("Automatic route already selected: \(destination).")
                return
            }
            try requireSafariFrontmost(pid)
            selectionAttempted = true
            try await accessibility.choose(named: destination, pid: pid)
            record("Automatic route requested: \(destination). Waiting for picker confirmation.")
            try await wait(1)
            let after = try await availablePickerControls(pid: pid, requiredNames: [destination])
            guard after.filter({ $0.name == destination && $0.selected == true }).count == 1 else {
                throw RoutingFailure(message: "Route ‘\(destination)’ was requested but could not be confirmed. Automatic routing stopped.")
            }
            try Task.checkCancellation()
            record("Automatic route selection confirmed: \(destination).")
        } catch {
            if !(error is CancellationError) {
                for note in await accessibility.diagnostics() { record("Picker diagnostic: \(note)") }
            }
            record(error is CancellationError ? "Automatic routing canceled." : "Automatic routing stopped: \(error.localizedDescription)")
            if selectionAttempted, let failure = error as? RoutingFailure {
                // A later missing picker does not prove that selection failed.
                throw RoutingFailure(message: failure.message)
            }
            throw error
        }
    }

    /// Destination rows arrive asynchronously. Do not toggle an already visible
    /// picker while waiting for them; retry the page button at most once, and
    /// only when repeated scans still expose no picker controls at all.
    private func availablePickerControls(pid: pid_t, requiredNames: [String]) async throws -> [RouteControl] {
        try requireSafariFrontmost(pid)
        controls = try await accessibility.inspectPicker(pid: pid)
        try requireSafariFrontmost(pid)
        if pickerContains(requiredNames) { return controls }
        if controls.isEmpty {
            record("Opening AirPlay picker; waiting for destination rows.")
            try await openPicker(pid: pid)
        } else {
            record("AirPlay picker controls are visible; waiting for destination rows without toggling it.")
        }
        if try await waitForPickerControls(pid: pid, requiredNames: requiredNames) { return controls }
        if controls.isEmpty {
            for note in await accessibility.diagnostics() { record("First picker wait: \(note)") }
            record("No picker controls appeared after the accessibility press. Trying verified mouse activation once.")
            try await openPicker(pid: pid, mouse: true)
            if try await waitForPickerControls(pid: pid, requiredNames: requiredNames) { return controls }
        }
        throw RoutingFailure(message: "AirPlay picker did not expose the required destination rows after a bounded wait. No destination was selected by this step.", retryableBeforeSelection: true)
    }

    private func pickerContains(_ names: [String]) -> Bool {
        !controls.isEmpty && names.allSatisfy { name in controls.contains { $0.name == name } }
    }

    private func waitForPickerControls(pid: pid_t, requiredNames: [String]) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + 2.5
        // The AX scanner has its own limit. Check the deadline between scans
        // and cap attempts too, so absent controls cannot start an endless loop.
        for attempt in 0..<6 {
            try requireSafariFrontmost(pid)
            controls = try await accessibility.inspectPicker(pid: pid)
            try requireSafariFrontmost(pid)
            if pickerContains(requiredNames) { return true }
            let remaining = deadline - ProcessInfo.processInfo.systemUptime
            guard attempt < 5, remaining > 0 else { break }
            try await wait(min(0.5, remaining))
        }
        return false
    }

    func cancel() {
        task?.cancel()
        record("Canceled. No further routing actions will be requested. Use Select TV if playback remains local.")
    }

    private func run(_ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { return }
        busy = true
        beginLog()
        task = Task {
            defer {
                busy = false
                task = nil
            }
            do { try await operation() }
            catch is CancellationError { record("Routing task stopped.") }
            catch {
                for note in await accessibility.diagnostics() { record("Picker diagnostic: \(note)") }
                record("Stopped: \(error.localizedDescription)")
            }
        }
    }

    private func beginLog() {
        controls = []
        history = ""
        logError = nil
        logURL = nil
        do {
            try FileManager.default.createDirectory(at: Self.logDirectory, withIntermediateDirectories: true)
            logURL = Self.logDirectory.appendingPathComponent("routing-\(UUID().uuidString).log")
        } catch { logError = error.localizedDescription }
    }

    private func prepareSafari() async throws -> pid_t {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else { throw RoutingFailure(message: "Enable Accessibility permission for SkyboxAudioProbe first.") }
        guard let safari = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.Safari").first else {
            throw RoutingFailure(message: "Open Safari with the streaming player active first.")
        }
        let pid = safari.processIdentifier
        if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return pid }
        record("Preparing Safari focus; current app: \(frontmostIdentity())")
        NSApp.yieldActivation(to: safari)
        let accepted = safari.activate(from: .current, options: [])
        record("Cooperative Safari activation accepted: \(accepted)")
        if try await waitForSafari(pid: pid, seconds: 1) { return pid }

        // Background AppKit activation is advisory. Use the Accessibility
        // permission already required by routing to request Safari foreground.
        // Never press a control until NSWorkspace independently confirms it.
        let result = try await accessibility.requestForeground(pid: pid)
        record("Safari Accessibility foreground request: \(result)")
        if try await waitForSafari(pid: pid, seconds: 2) { return pid }
        throw RoutingFailure(message: "Safari activation was not confirmed (frontmost: \(frontmostIdentity())). No picker control was pressed.")
    }

    private func waitForSafari(pid: pid_t, seconds: Double) async throws -> Bool {
        let deadline = ProcessInfo.processInfo.systemUptime + seconds
        while ProcessInfo.processInfo.systemUptime < deadline {
            try Task.checkCancellation()
            if NSWorkspace.shared.frontmostApplication?.processIdentifier == pid { return true }
            try await wait(0.1)
        }
        return NSWorkspace.shared.frontmostApplication?.processIdentifier == pid
    }

    private func frontmostIdentity() -> String {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? "unknown"
    }

    private func openPicker(pid: pid_t, mouse: Bool = false) async throws {
        try Task.checkCancellation()
        try requireSafariFrontmost(pid)
        try await accessibility.openPicker(pid: pid, mouse: mouse)
        for note in await accessibility.diagnostics() { record("Page button: \(note)") }
        try await wait(0.8)
        try requireSafariFrontmost(pid)
    }

    private func requireSafariFrontmost(_ pid: pid_t) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RoutingFailure(
                message: "Focus moved away from Safari (frontmost: \(frontmostIdentity())). Stopped to avoid acting in another app.",
                focusReturnedToCommercialBreaker: NSWorkspace.shared.frontmostApplication?.processIdentifier == ProcessInfo.processInfo.processIdentifier)
        }
    }

    private func wait(_ seconds: Double) async throws {
        try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
    }

    private func record(_ message: String) {
        status = message
        history += "\(Date().ISO8601Format()) · \(message)\n"
        if let logURL {
            do { try history.write(to: logURL, atomically: true, encoding: .utf8) }
            catch { logError = "Could not save routing log: \(error.localizedDescription)" }
        }
    }
}
