import Foundation

let choices = [
    AirPlayRouteChoice(id: 1, name: "This Computer", enabled: true),
    AirPlayRouteChoice(id: 2, name: "Living Room", enabled: true),
    AirPlayRouteChoice(id: 3, name: "Living Room", enabled: false)
]
precondition(try! AirPlayRouteSelection.select(named: " Living Room\n", from: choices).id == 2)
precondition(try! AirPlayRouteSelection.select(named: "This Computer", from: choices).id == 1)
func expect(_ expected: AirPlayRouteSelectionError, _ name: String, _ input: [AirPlayRouteChoice]) {
    do {
        _ = try AirPlayRouteSelection.select(named: name, from: input)
        fatalError("Selection should fail")
    } catch let error as AirPlayRouteSelectionError { precondition(error == expected) }
    catch { fatalError("Unexpected error: \(error)") }
}
expect(.emptyName, " \n ", choices)
expect(.notFound, "living room", choices)
expect(.notFound, "Living", choices)
expect(.notFound, "Bedroom", choices)
expect(.notFound, "Living Room", Array(choices.suffix(1)))
expect(.ambiguous, "Living Room", choices + [AirPlayRouteChoice(id: 4, name: " Living Room ", enabled: true)])
expect(.notFound, "Living Room", [])
print("AirPlay route selection checks passed")
