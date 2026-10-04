import Foundation

/// A selectable destination discovered in the AirPlay picker's Accessibility tree.
/// IDs are temporary identifiers for one scan, not persistent Apple TV identities.
struct AirPlayRouteChoice: Equatable {
    let id: Int
    let name: String
    let enabled: Bool
}

enum AirPlayRouteSelectionError: Error, Equatable {
    case emptyName
    case notFound
    case ambiguous
}

enum AirPlayRouteSelection {
    /// Returns the unique enabled destination whose trimmed name matches exactly.
    /// Case is significant: selecting the wrong output is worse than asking to retry.
    static func select(named name: String, from choices: [AirPlayRouteChoice]) throws -> AirPlayRouteChoice {
        let target = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !target.isEmpty else { throw AirPlayRouteSelectionError.emptyName }
        let matches = choices.filter {
            $0.enabled && $0.name.trimmingCharacters(in: .whitespacesAndNewlines) == target
        }
        guard !matches.isEmpty else { throw AirPlayRouteSelectionError.notFound }
        guard matches.count == 1 else { throw AirPlayRouteSelectionError.ambiguous }
        return matches[0]
    }
}
