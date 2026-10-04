import Foundation
let panel = [(role: "AXButton", name: "Try AirPlay"),
             (role: "AXButton", name: "Restore settings and close"),
             (role: "AXTextArea", name: "AirPlay connection history")]
assert(SafariAccessibility.isSkyboxPanel(panel))
assert(!SafariAccessibility.isSkyboxPanel(Array(panel.prefix(1))))
assert(SafariAccessibility.isSkyboxPanel(Array(panel.prefix(2))))
assert(!SafariAccessibility.isSkyboxPanel(panel + [panel[0]]))
assert(!SafariAccessibility.isSkyboxPanel([(role: "AXStaticText", name: "Try AirPlay")] + panel.dropFirst()))
print("Skybox panel checks passed: exact roles, companion controls, duplicate rejection")

// A flattened page can be large; only adjacent controls qualify as companions.
let page = Array(repeating: (role: "AXButton", name: "Unrelated"), count: 100)
var flattened = page
flattened.replaceSubrange(50..<53, with: panel)
let neighborhood = SafariAccessibility.panelNeighborhood(index: 50, count: flattened.count)
assert(SafariAccessibility.isSkyboxPanel(Array(flattened[neighborhood])))
flattened[51] = (role: "AXButton", name: "Unrelated")
flattened[90] = panel[1]
assert(!SafariAccessibility.isSkyboxPanel(Array(flattened[neighborhood])))
assert(SafariAccessibility.panelNeighborhood(index: 0, count: 2) == 0..<2)
assert(SafariAccessibility.panelNeighborhood(index: 99, count: 100) == 95..<100)
print("Flattened panel checks passed: nearby companions, distant rejection, page edges")

let relay = ["Play", "Choose AirPlay", "Mute", "Check playback", "Stop playback"]
    .map { (role: "AXButton", name: $0) }
assert(SafariAccessibility.isPlayerPanel(relay, buttonName: "Choose AirPlay"))
assert(SafariAccessibility.isPlayerPanel(panel, buttonName: "Try AirPlay"))
assert(!SafariAccessibility.isPlayerPanel(relay, buttonName: "Try AirPlay"))
assert(!SafariAccessibility.isPlayerPanel(panel, buttonName: "Choose AirPlay"))
assert(!SafariAccessibility.isPlayerPanel(relay + [relay[1]], buttonName: "Choose AirPlay"))
assert(!SafariAccessibility.isPlayerPanel(Array(relay.prefix(4)), buttonName: "Choose AirPlay"))
let wrongRoles = relay.map { (role: "AXStaticText", name: $0.name) }
assert(!SafariAccessibility.isPlayerPanel(wrongRoles, buttonName: "Choose AirPlay"))
let relayPage = page + relay + page
let relayNeighborhood = SafariAccessibility.panelNeighborhood(index: 101, count: relayPage.count)
assert(SafariAccessibility.isPlayerPanel(Array(relayPage[relayNeighborhood]), buttonName: "Choose AirPlay"))
print("Relay controls checks passed: exact companions, roles, duplicate rejection, flattened layout")
