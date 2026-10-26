import ApplicationServices
import AppKit
import Foundation

struct RouteControl: Sendable {
    let name: String
    let role: String
    let enabled: Bool
    let selected: Bool?
}

struct RoutingFailure: LocalizedError {
    let message: String
    var retryableBeforeSelection = false
    var focusReturnedToCommercialBreaker = false
    var errorDescription: String? { message }
}

/// Serializes cross-process AX calls away from the app's UI thread.
actor SafariAccessibility {
    private var scanNotes: [String] = []
    func diagnostics() -> [String] { scanNotes }
    private struct Control {
        let element: AXUIElement
        let info: RouteControl
    }

    private var cachedPageButton: AXUIElement?

    func requestForeground(pid: pid_t) throws -> Int32 {
        try Task.checkCancellation()
        guard AXIsProcessTrusted() else {
            throw RoutingFailure(message: "Enable Accessibility permission for SkyboxAudioProbe first.")
        }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        return AXUIElementSetAttributeValue(app, kAXFrontmostAttribute as CFString, kCFBooleanTrue).rawValue
    }

    func openPicker(pid: pid_t, mouse: Bool = false) async throws {
        scanNotes = ["Looking for the Commercial Breaker page panel"]
        guard AXIsProcessTrusted() else { throw RoutingFailure(message: "Enable Accessibility permission for SkyboxAudioProbe first.") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        guard let mainValue = value(app, kAXMainWindowAttribute), CFGetTypeID(mainValue) == AXUIElementGetTypeID() else {
            throw RoutingFailure(message: "Safari's main window is not accessible.")
        }
        let main = unsafeBitCast(mainValue, to: AXUIElement.self)
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        if let cachedPageButton, belongsToWindow(cachedPageButton, main: main),
           try isCommercialBreakerButton(cachedPageButton, deadline: deadline) {
            scanNotes.append("Reusing verified Commercial Breaker panel button in the current window")
            try await activatePageButton(cachedPageButton, pid: pid, mouse: mouse)
            return
        }
        cachedPageButton = nil
        var pending: [(AXUIElement, Int)] = [(main, 0)]
        var seen: [AXUIElement] = []
        while let (element, depth) = pending.popLast() {
            try Task.checkCancellation()
            guard seen.count < 2400, ProcessInfo.processInfo.systemUptime < deadline else {
                scanNotes.append("Commercial Breaker panel search stopped after \(seen.count) elements")
                throw RoutingFailure(message: "Commercial Breaker panel search exceeded its limit. Show the Commercial Breaker extension panel or HLS relay player in the active Safari tab.")
            }
            guard !seen.contains(where: { CFEqual($0, element) }) else { continue }
            seen.append(element)
            if try isCommercialBreakerButton(element, deadline: deadline) {
                scanNotes.append("Verified Commercial Breaker panel after \(seen.count) elements; unrelated page traversal skipped")
                cachedPageButton = element
                try await activatePageButton(element, pid: pid, mouse: mouse)
                return
            }
            if depth < 40, let children = value(element, kAXChildrenAttribute) as? [AXUIElement] {
                // The extension appends its floating panel after the site's content.
                // Visit trailing children first instead of walking the entire guide.
                pending += children.map { ($0, depth + 1) }
            }
        }
        scanNotes.append("Page search completed: \(seen.count) distinct elements")
        throw RoutingFailure(message: "Commercial Breaker's AirPlay button was not found with its companion controls. Show the extension panel (Try AirPlay) or HLS relay player (Choose AirPlay) in the active Safari tab.")
    }

    private func activatePageButton(_ button: AXUIElement, pid: pid_t, mouse: Bool) async throws {
        guard mouse else { try press(button, pid: pid); return }
        try Task.checkCancellation()
        guard CGPreflightPostEventAccess(),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RoutingFailure(message: "Safari must be foreground and event-post permission enabled. No mouse click sent.")
        }
        guard let position = value(button, kAXPositionAttribute),
              let size = value(button, kAXSizeAttribute),
              CFGetTypeID(position) == AXValueGetTypeID(), CFGetTypeID(size) == AXValueGetTypeID() else {
            throw RoutingFailure(message: "AirPlay button bounds unavailable. No mouse click sent.")
        }
        var origin = CGPoint.zero
        var dimensions = CGSize.zero
        guard AXValueGetValue(unsafeBitCast(position, to: AXValue.self), .cgPoint, &origin),
              AXValueGetValue(unsafeBitCast(size, to: AXValue.self), .cgSize, &dimensions),
              origin.x.isFinite, origin.y.isFinite,
              dimensions.width.isFinite, dimensions.height.isFinite,
              dimensions.width > 0, dimensions.height > 0 else {
            throw RoutingFailure(message: "AirPlay button bounds invalid. No mouse click sent.")
        }
        let point = CGPoint(x: origin.x + dimensions.width / 2, y: origin.y + dimensions.height / 2)
        var hit: AXUIElement?
        guard point.x.isFinite, point.y.isFinite,
              AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &hit) == .success,
              let hit, CFEqual(hit, button) else {
            throw RoutingFailure(message: "AirPlay button is obscured or its hit target differs. No mouse click sent.")
        }
        guard let down = CGEvent(mouseEventSource: nil, mouseType: .leftMouseDown, mouseCursorPosition: point, mouseButton: .left),
              let up = CGEvent(mouseEventSource: nil, mouseType: .leftMouseUp, mouseCursorPosition: point, mouseButton: .left) else {
            throw RoutingFailure(message: "Could not create AirPlay mouse events.")
        }
        down.flags = []; up.flags = []
        down.setIntegerValueField(.mouseEventClickState, value: 1)
        up.setIntegerValueField(.mouseEventClickState, value: 1)
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RoutingFailure(message: "Safari lost focus before mouse activation. No click sent.")
        }
        // Use WindowServer's mouse-event path: process-directed events did not
        // open Safari's picker in the live test. Recheck the global hit target
        // immediately before posting; never suspend between down and up.
        var finalHit: AXUIElement?
        guard AXUIElementCopyElementAtPosition(AXUIElementCreateSystemWide(), Float(point.x), Float(point.y), &finalHit) == .success,
              let finalHit, CFEqual(finalHit, button),
              NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RoutingFailure(message: "AirPlay click target changed. No click sent.")
        }
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
        scanNotes.append("System mouse click posted at the verified AirPlay button hit target")
    }

    private func belongsToWindow(_ element: AXUIElement, main: AXUIElement) -> Bool {
        var current = element
        for _ in 0..<40 {
            if CFEqual(current, main) { return true }
            guard let parent = value(current, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { return false }
            current = unsafeBitCast(parent, to: AXUIElement.self)
        }
        return false
    }

    /// Identify the extension panel or relay's bounded player controls, not the first similarly named
    /// button elsewhere on the website. Inspect only labels, never history values.
    private func isCommercialBreakerButton(_ element: AXUIElement, deadline: Double) throws -> Bool {
        guard value(element, kAXRoleAttribute) as? String == "AXButton",
              ["Try AirPlay", "Choose AirPlay"].contains(label(element)),
              (value(element, kAXEnabledAttribute) as? NSNumber)?.boolValue == true else { return false }
        var actions: CFArray?
        guard AXUIElementCopyActionNames(element, &actions) == .success,
              (actions as? [String])?.contains(kAXPressAction) == true else { return false }
        let buttonName = label(element)
        scanNotes.append("Found enabled \(buttonName); validating nearby player controls")
        var ancestor = element
        // Safari may insert accessibility groups between a DOM button and its
        // section. Inspect a few small ancestors rather than assuming its parent
        // contains all of the panel's siblings.
        for _ in 0..<4 {
            guard let parent = value(ancestor, kAXParentAttribute), CFGetTypeID(parent) == AXUIElementGetTypeID() else { break }
            ancestor = unsafeBitCast(parent, to: AXUIElement.self)
            let isPage = value(ancestor, kAXRoleAttribute) as? String == "AXWebArea"
            var pending = [ancestor]
            if isPage {
                // WebKit can flatten an unlabelled HTML section into the web
                // area's direct children. Check only the button's neighborhood.
                guard let siblings = value(ancestor, kAXChildrenAttribute) as? [AXUIElement],
                      let index = siblings.firstIndex(where: { CFEqual($0, element) }) else { break }
                pending = Array(siblings[Self.panelNeighborhood(index: index, count: siblings.count)])
                scanNotes.append("Panel is flattened into the webpage; checking adjacent controls")
            }
            var seen: [AXUIElement] = []
            var labels: [(role: String, name: String)] = []
            var complete = true
            while let node = pending.popLast() {
                try Task.checkCancellation()
                guard seen.count < 80, ProcessInfo.processInfo.systemUptime < deadline else { complete = false; break }
                guard !seen.contains(where: { CFEqual($0, node) }) else { continue }
                seen.append(node)
                let role = value(node, kAXRoleAttribute) as? String ?? ""
                labels.append((role, label(node)))
                if !isPage, let children = value(node, kAXChildrenAttribute) as? [AXUIElement] { pending += children }
            }
            // Require a complete small subtree so ambiguity cannot be hidden by
            // the search limit. History's accessible label is not needed to press.
            if complete && Self.isPlayerPanel(labels, buttonName: buttonName) { return true }
            scanNotes.append("Panel ancestor checked: \(seen.count) elements; companion controls not verified")
            if isPage { break }
        }
        return false
    }

    nonisolated static func panelNeighborhood(index: Int, count: Int) -> Range<Int> {
        max(0, index - 4)..<min(count, index + 5)
    }

    nonisolated static func isCommercialBreakerPanel(_ labels: [(role: String, name: String)]) -> Bool {
        labels.filter { $0.role == "AXButton" && $0.name == "Try AirPlay" }.count == 1
        && labels.contains { $0.role == "AXButton" && $0.name == "Restore settings and close" }

    }

    /// The relay's existing page exposes these adjacent controls even when
    /// WebKit flattens the HTML into direct web-area children.
    nonisolated static func isPlayerPanel(_ labels: [(role: String, name: String)], buttonName: String) -> Bool {
        if buttonName == "Try AirPlay" { return isCommercialBreakerPanel(labels) }
        guard buttonName == "Choose AirPlay" else { return false }
        return ["Choose AirPlay", "Play", "Check playback", "Stop playback"].allSatisfy { name in
            labels.filter { $0.role == "AXButton" && $0.name == name }.count == 1
        }
    }

    private func label(_ element: AXUIElement) -> String {
        let title = value(element, kAXTitleAttribute) as? String
        return title?.isEmpty == false ? title! : (value(element, kAXDescriptionAttribute) as? String ?? "")
    }

    func inspectPicker(pid: pid_t) throws -> [RouteControl] {
        try scanPicker(pid: pid).map(\.info)
    }

    func choose(named name: String, pid: pid_t) throws {
        let controls = try scanPicker(pid: pid)
        let choices = controls.enumerated().map {
            AirPlayRouteChoice(id: $0.offset, name: $0.element.info.name, enabled: $0.element.info.enabled)
        }
        let selected: AirPlayRouteChoice
        do { selected = try AirPlayRouteSelection.select(named: name, from: choices) }
        catch { throw RoutingFailure(message: "No unique enabled picker control named ‘\(name)’. Use Inspect picker and copy its exact label. (\(error))") }
        try press(controls[selected.id].element, pid: pid)
    }

    private func press(_ element: AXUIElement, pid: pid_t) throws {
        try Task.checkCancellation()
        guard NSWorkspace.shared.frontmostApplication?.processIdentifier == pid else {
            throw RoutingFailure(message: "Safari lost focus during the scan. No control was pressed.")
        }
        let result = AXUIElementPerformAction(element, kAXPressAction as CFString)
        guard result == .success else { throw RoutingFailure(message: "Accessibility press failed: \(result.rawValue). No coordinate-click fallback was attempted.") }
    }

    private func value(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var result: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &result) == .success else { return nil }
        return result
    }

    /// Safari exposes the AirPlay destination text beside an unnamed checkbox.
    /// Only accept one distinct static-text label inside that same picker row.
    private func rowLabel(_ row: AXUIElement, deadline: Double) throws -> String {
        var pending = [row]
        var seen: [AXUIElement] = []
        var labels = Set<String>()
        while let element = pending.popLast() {
            try Task.checkCancellation()
            guard seen.count < 64, ProcessInfo.processInfo.systemUptime < deadline else {
                throw RoutingFailure(message: "Picker row label scan exceeded its limit. No destination selected.")
            }
            guard !seen.contains(where: { CFEqual($0, element) }) else { continue }
            seen.append(element)
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            if role == "AXStaticText" {
                let text = (value(element, kAXValueAttribute) as? String)
                    ?? (value(element, kAXTitleAttribute) as? String) ?? ""
                let label = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if !label.isEmpty, label.count <= 160, !label.contains("://") { labels.insert(label) }
            }
            if let children = value(element, kAXChildrenAttribute) as? [AXUIElement] { pending += children }
        }
        return labels.count == 1 ? labels.first! : ""
    }

    private func scanPicker(pid: pid_t) throws -> [Control] {
        let native = try scan(pid: pid, includeWeb: false)
        guard native.isEmpty else { return native }
        let nativeNotes = scanNotes
        defer { scanNotes = nativeNotes + ["No native rows outside webpage; searching embedded picker containers"] + scanNotes }
        return try scan(pid: pid, includeWeb: false, explorePage: true)
    }

    private func scan(pid: pid_t, includeWeb: Bool, explorePage: Bool = false) throws -> [Control] {
        scanNotes = []
        guard AXIsProcessTrusted() else { throw RoutingFailure(message: "Enable SkyboxAudioProbe in System Settings → Privacy & Security → Accessibility.") }
        let app = AXUIElementCreateApplication(pid)
        AXUIElementSetMessagingTimeout(app, 0.25)
        // Scan the front Safari window plus non-browser popup windows. Never search
        // other tabs/windows for a second page's Try AirPlay button.
        guard let mainValue = value(app, kAXMainWindowAttribute), CFGetTypeID(mainValue) == AXUIElementGetTypeID() else {
            throw RoutingFailure(message: "Safari's main window is not accessible. Bring the streaming window forward and retry.")
        }
        let main = unsafeBitCast(mainValue, to: AXUIElement.self)
        var roots = [main]
        if !includeWeb, let windows = value(app, kAXWindowsAttribute) as? [AXUIElement] {
            roots += windows.filter { !CFEqual($0, main) && (value($0, kAXSubroleAttribute) as? String) != kAXStandardWindowSubrole }
        }
        if !includeWeb {
            scanNotes.append("Safari scan roots: \(roots.count)")
            let system = AXUIElementCreateSystemWide()
            AXUIElementSetMessagingTimeout(system, 0.25)
            if let focused = value(system, kAXFocusedUIElementAttribute), CFGetTypeID(focused) == AXUIElementGetTypeID() {
                let element = unsafeBitCast(focused, to: AXUIElement.self)
                var owner: pid_t = 0
                let result = AXUIElementGetPid(element, &owner)
                let bundle = NSRunningApplication(processIdentifier: owner)?.bundleIdentifier ?? "unknown"
                let role = value(element, kAXRoleAttribute) as? String ?? "unknown"
                scanNotes.append("Focused AX owner: \(bundle); pid=\(owner); role=\(role); status=\(result.rawValue)")
            } else { scanNotes.append("Focused AX element unavailable") }
        }
        var roleCounts: [String: Int] = [:]
        var outsidePressable = 0
        var unnamedPressable = 0
        defer {
            if !includeWeb {
                scanNotes.append("Roles: " + roleCounts.keys.sorted().map { "\($0)=\(roleCounts[$0]!)" }.joined(separator: ", "))
                scanNotes.append("Excluded pressable controls outside picker: \(outsidePressable); unnamed pressable controls: \(unnamedPressable)")
            }
        }
        var stack: [(AXUIElement, Int, Bool, AXUIElement?)] = roots.map { ($0, 0, !CFEqual($0, main), nil) }
        var seen: [AXUIElement] = []
        var controls: [Control] = []
        let deadline = ProcessInfo.processInfo.systemUptime + 5
        var visited = 0
        while let (element, depth, inPicker, parentRow) = stack.popLast() {
            try Task.checkCancellation()
            guard visited < (explorePage ? 3000 : 1200), ProcessInfo.processInfo.systemUptime < deadline else {
                throw RoutingFailure(message: "Accessibility scan exceeded its limit. No control was selected; keep only the streaming page visible and retry.")
            }
            guard !seen.contains(where: { CFEqual($0, element) }) else { continue }
            seen.append(element)
            visited += 1
            let role = value(element, kAXRoleAttribute) as? String ?? ""
            roleCounts[role, default: 0] += 1
            if !explorePage && role == "AXWebArea" { continue }
            let row = role == "AXRow" ? element : parentRow
            let pickerContext = inPicker || ["AXPopover", "AXMenu", "AXSheet", "AXDialog"].contains(role)
            if (!explorePage || pickerContext) && ["AXButton", "AXRadioButton", "AXCheckBox", "AXMenuItem", "AXRow"].contains(role) {
                var actions: CFArray?
                if AXUIElementCopyActionNames(element, &actions) == .success,
                   (actions as? [String])?.contains(kAXPressAction) == true {
                    let title = value(element, kAXTitleAttribute) as? String
                    let description = value(element, kAXDescriptionAttribute) as? String
                    var name = (title?.isEmpty == false ? title : description) ?? ""
                    if name.isEmpty && pickerContext && ["AXCheckBox", "AXRadioButton"].contains(role), let row {
                        name = try rowLabel(row, deadline: deadline)
                    }
                    if !includeWeb && !pickerContext { outsidePressable += 1 }
                    if name.isEmpty { unnamedPressable += 1 }
                    if !includeWeb && scanNotes.count < 50 && (pickerContext || ["AXRadioButton", "AXCheckBox"].contains(role)) {
                        let safeName = name.count <= 160 && !name.contains("://") ? name : "[omitted]"
                        scanNotes.append("Candidate: role=\(role); pickerContext=\(pickerContext); label=\(safeName)")
                    }
                    // Do not persist page content, URLs, text-field values, or entire AX trees.
                    if (includeWeb || pickerContext) && !name.isEmpty && name.count <= 160 && !name.contains("://") {
                        let enabled = (value(element, kAXEnabledAttribute) as? NSNumber)?.boolValue ?? false
                        var selected = (value(element, kAXSelectedAttribute) as? NSNumber)?.boolValue
                        if selected == nil && ["AXRadioButton", "AXCheckBox"].contains(role) {
                            selected = (value(element, kAXValueAttribute) as? NSNumber)?.boolValue
                        }
                        controls.append(Control(element: element, info: RouteControl(name: name, role: role, enabled: enabled, selected: selected)))
                    }
                }
            }
            if let children = value(element, kAXChildrenAttribute) as? [AXUIElement], !children.isEmpty {
                guard depth < (explorePage ? 40 : 30) else { throw RoutingFailure(message: "Accessibility tree was too deep; scan is incomplete.") }
                stack += children.reversed().map { ($0, depth + 1, pickerContext, row) }
            }
        }
        return controls
    }
}
